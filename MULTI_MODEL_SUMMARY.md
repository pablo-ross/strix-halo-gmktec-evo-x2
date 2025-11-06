# Multi-Model Setup Summary

Quick reference guide for your multi-model LLM deployment.

## What Was Done

✅ **Continue.dev Configuration** (`~/.continue/config.json`)
- Fixed context size: 258,048 tokens (252K)
- Ready for multi-model setup (docs in `~/.continue/MULTI_MODEL_SETUP.md`)

✅ **Qwen Code Configuration** (`~/.qwen/settings.json`)
- Added `sessionTokenLimit`: 258,048 tokens
- Ready for multi-model setup (docs in `~/.qwen/MULTI_MODEL_SETUP.md`)

✅ **Wrapper Scripts** (`/home/mornel/wrappers/`)
- `qwen3-coder-server.sh` - Main chat (active on port 8080)
- `qwen25-7b-autocomplete-server.sh` - Fast autocomplete (port 8082, commented)
- `nomic-embed-server.sh` - Embeddings (port 8083, commented)
- `deepseek-r1-reasoning-server.sh` - Reasoning (port 8084, commented)

✅ **Systemd Services** (`/home/mornel/ubuntu-setup/systemctl/`)
- `qwen25-7b-server.service` - Ready to install
- `nomic-embed-server.service` - Ready to install
- `deepseek-r1-server.service` - Ready to install

✅ **Documentation**
- `MULTI_MODEL_DEPLOYMENT.md` - Complete deployment guide
- `~/.continue/MULTI_MODEL_SETUP.md` - Continue.dev specific
- `~/.qwen/MULTI_MODEL_SETUP.md` - Qwen Code specific

## Current Status

### Active (Working Now)
- ✅ Qwen3-Coder-30B Q8 (port 8080) - Main chat, complex coding
- ✅ Bielik-11B (port 8081) - Polish language
- ✅ Nginx API Gateway - Routes traffic to models
- ✅ Context size fixed for Continue.dev and Qwen Code

### Prepared (Ready to Enable)
- ⏸️ Qwen2.5-Coder-7B (port 8082) - Fast autocomplete
- ⏸️ Nomic Embed v2 (port 8083) - Embeddings
- ⏸️ DeepSeek R1 32B (port 8084) - Reasoning

## When You're Ready to Enable Multi-Model

### Step 1: Download Nomic Embed (only missing model)

```bash
distrobox enter llama-rocm-7rc-rocwmma
export HF_HUB_ENABLE_HF_TRANSFER=1
hf download nomic-ai/nomic-embed-text-v2-moe-GGUF \
  nomic-embed-text-v2-moe-f16.gguf \
  --local-dir ~/models
exit
```

### Step 2: Install Systemd Services

```bash
cd ~/ubuntu-setup/systemctl
sudo cp qwen25-7b-server.service /etc/systemd/system/
sudo cp nomic-embed-server.service /etc/systemd/system/
sudo cp deepseek-r1-server.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### Step 3: Start New Services

```bash
# Enable to start on boot
sudo systemctl enable qwen25-7b-server
sudo systemctl enable nomic-embed-server

# Start now
sudo systemctl start qwen25-7b-server
sudo systemctl start nomic-embed-server

# Check status
sudo systemctl status qwen25-7b-server
sudo systemctl status nomic-embed-server
```

### Step 4: Update Nginx

Add the new upstream routes from `MULTI_MODEL_DEPLOYMENT.md` to `/etc/nginx/nginx.conf`:

```bash
sudo nano /etc/nginx/nginx.conf
# Add upstreams and location blocks for qwen25-7b, nomic-embed, deepseek-r1
sudo nginx -t
sudo systemctl reload nginx
```

### Step 5: Update Client Configs

**Continue.dev:**
```bash
# Backup current config
cp ~/.continue/config.json ~/.continue/config.json.backup

# Replace with multi-model config from:
# ~/.continue/MULTI_MODEL_SETUP.md

# Restart VS Code to pick up changes
```

**Qwen Code:**
```bash
# Add aliases to ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# Qwen multi-model aliases
alias qwen-reasoning='OPENAI_BASE_URL=http://127.0.0.1/deepseek-r1/v1 qwen'
alias qwen-fast='OPENAI_BASE_URL=http://127.0.0.1/qwen25-7b/v1 qwen'
EOF

source ~/.bashrc
```

### Step 6: Test Everything

```bash
# Test all endpoints
curl http://localhost:8080/health  # Qwen3-30B ✓
curl http://localhost:8082/health  # Qwen2.5-7B (new)
curl http://localhost:8083/health  # Nomic Embed (new)

# Test via nginx
curl http://10.0.0.60/v1/models
curl http://10.0.0.60/qwen25-7b/v1/models
curl http://10.0.0.60/nomic-embed/v1/models
```

## Expected Performance Improvements

| Task | Current (Single Model) | Multi-Model | Gain |
|------|------------------------|-------------|------|
| Tab autocomplete | ~50ms | ~15ms | **3.3x faster** |
| Embeddings | ~500ms | ~50ms | **10x faster** |
| Quick questions | ~80ms | ~25ms | **3.2x faster** |
| Reasoning | Good | Excellent | **Better quality** |

## Memory Usage

**Current (2 models):**
```
Qwen3-30B: 40GB
Bielik-11B: 8GB
───────────────
Total:     48GB / 120GB
Free:      72GB
```

**After Multi-Model (5 models):**
```
Qwen3-30B:     40GB  (always)
Bielik-11B:     8GB  (always)
Qwen2.5-7B:     8GB  (always)
Nomic Embed:    3GB  (always)
DeepSeek R1:   24GB  (on-demand)
────────────────────────────
Total:         83GB  (all at once)
OR             59GB  (without DeepSeek)
Free:          37GB  (worst case)
               61GB  (typical)
```

## Port Assignments

| Port | Service | Model | Status |
|------|---------|-------|--------|
| 8080 | llama-server | Qwen3-Coder-30B Q8 | ✅ Active |
| 8081 | bielik-server | Bielik-11B | ✅ Active |
| 8082 | qwen25-7b-server | Qwen2.5-Coder-7B | ⏸️ Ready |
| 8083 | nomic-embed-server | Nomic Embed v2 | ⏸️ Ready |
| 8084 | deepseek-r1-server | DeepSeek R1 32B | ⏸️ Ready |

## Quick Commands Reference

```bash
# Service management
sudo systemctl status qwen25-7b-server
sudo systemctl start qwen25-7b-server
sudo systemctl stop qwen25-7b-server
sudo systemctl restart qwen25-7b-server

# View logs
sudo journalctl -u qwen25-7b-server -f

# Test models
curl http://localhost:8082/health
curl http://10.0.0.60/qwen25-7b/v1/models

# Use from Qwen CLI
qwen "question"                    # Uses main model (Qwen3-30B)
qwen-fast "quick question"         # Uses 7B model (when enabled)
qwen-reasoning "complex problem"   # Uses DeepSeek R1 (when enabled)
```

## Files You Need to Know

| File | Purpose |
|------|---------|
| `MULTI_MODEL_DEPLOYMENT.md` | Complete deployment guide |
| `~/.continue/MULTI_MODEL_SETUP.md` | Continue.dev configuration |
| `~/.qwen/MULTI_MODEL_SETUP.md` | Qwen Code configuration |
| `/home/mornel/wrappers/*.sh` | Server startup scripts |
| `/home/mornel/ubuntu-setup/systemctl/*.service` | Systemd service definitions |

## Need Help?

All commented configurations are ready to use. Just:
1. Follow the steps in `MULTI_MODEL_DEPLOYMENT.md`
2. Uncomment/enable the features you want
3. Test each step before moving to the next

The current setup will keep working perfectly while you prepare the multi-model deployment!
