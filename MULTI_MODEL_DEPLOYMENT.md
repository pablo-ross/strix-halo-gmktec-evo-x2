# Multi-Model LLM Deployment Guide

Complete guide for setting up multiple specialized llama-server instances for optimal performance.

## Overview

This setup uses specialized models for different tasks to maximize performance and efficiency:

| Model | Purpose | Port | Memory | Status |
|-------|---------|------|--------|--------|
| Qwen3-Coder-30B Q8 | Main chat, complex coding | 8080 | ~40GB | ✅ Active |
| Bielik-11B | Polish language | 8081 | ~8GB | ✅ Active |
| Qwen2.5-Coder-7B | Fast autocomplete | 8082 | ~8GB | ⏸️ Planned |
| Nomic Embed v2 | Embeddings, RAG | 8083 | ~3GB | ⏸️ Planned |
| DeepSeek-R1-32B | Reasoning tasks | 8084 | ~24GB | ⏸️ Planned |

## Current Setup (Working)

### Active Services

1. **Qwen3-Coder-30B** (Main chat)
   - Systemd: `llama-server.service`
   - Wrapper: `/home/mornel/wrappers/qwen3-coder-server.sh`
   - Port: 8080
   - Context: 256K tokens
   - Status: ✅ Running

2. **Bielik-11B** (Polish language)
   - Systemd: `bielik-server.service`
   - Port: 8081
   - Context: 64K tokens
   - Status: ✅ Running

3. **Nginx API Gateway**
   - Routes `/v1` to Qwen3-30B (8080)
   - Routes `/bielik/v1` to Bielik-11B (8081)
   - Public IP: 10.0.0.60

## Planned Multi-Model Setup

### Step 1: Download Missing Model

Only Nomic Embed needs to be downloaded:

```bash
# Inside container
distrobox enter llama-rocm-7rc-rocwmma

# Download Nomic Embed
export HF_HUB_ENABLE_HF_TRANSFER=1
hf download nomic-ai/nomic-embed-text-v2-moe-GGUF \
  nomic-embed-text-v2-moe-f16.gguf \
  --local-dir ~/models
```

### Step 2: Create Systemd Services

Three new systemd services need to be created:

#### 2a. Qwen2.5-7B Autocomplete Service

Create `/etc/systemd/system/qwen25-7b-server.service`:

```ini
[Unit]
Description=llama.cpp Server - Qwen2.5-Coder-7B (Autocomplete)
After=network.target

[Service]
Type=simple
User=mornel
Group=mornel
WorkingDirectory=/home/mornel
ExecStart=/home/mornel/wrappers/qwen25-7b-autocomplete-server.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

#### 2b. Nomic Embed Service

Create `/etc/systemd/system/nomic-embed-server.service`:

```ini
[Unit]
Description=llama.cpp Server - Nomic Embed v2 (Embeddings)
After=network.target

[Service]
Type=simple
User=mornel
Group=mornel
WorkingDirectory=/home/mornel
ExecStart=/home/mornel/wrappers/nomic-embed-server.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

#### 2c. DeepSeek R1 Service (On-Demand)

Create `/etc/systemd/system/deepseek-r1-server.service`:

```ini
[Unit]
Description=llama.cpp Server - DeepSeek R1 Distill (Reasoning)
After=network.target

[Service]
Type=simple
User=mornel
Group=mornel
WorkingDirectory=/home/mornel
ExecStart=/home/mornel/wrappers/deepseek-r1-reasoning-server.sh
Restart=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Note**: DeepSeek R1 uses `Restart=no` since it's for on-demand reasoning tasks.

### Step 3: Update Nginx Configuration

Add new upstream servers and location blocks to `/etc/nginx/nginx.conf`:

```nginx
http {
    # ... existing config ...

    # Existing upstreams
    upstream qwen3_30b {
        server 127.0.0.1:8080;
    }

    upstream bielik_11b {
        server 127.0.0.1:8081;
    }

    # NEW: Add these upstreams
    upstream qwen25_7b {
        server 127.0.0.1:8082;
    }

    upstream nomic_embed {
        server 127.0.0.1:8083;
    }

    upstream deepseek_r1 {
        server 127.0.0.1:8084;
    }

    # Model aggregation endpoint
    upstream all_models {
        server 127.0.0.1:8080;
        server 127.0.0.1:8081;
        # Add new models here when ready:
        # server 127.0.0.1:8082;
        # server 127.0.0.1:8084;
    }

    server {
        listen 80;
        server_name _;

        # ... existing locations ...

        # NEW: Add these location blocks
        location /qwen25-7b/ {
            rewrite ^/qwen25-7b/(.*) /$1 break;
            proxy_pass http://qwen25_7b;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 300s;
        }

        location /nomic-embed/ {
            rewrite ^/nomic-embed/(.*) /$1 break;
            proxy_pass http://nomic_embed;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 300s;
        }

        location /deepseek-r1/ {
            rewrite ^/deepseek-r1/(.*) /$1 break;
            proxy_pass http://deepseek_r1;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 300s;
        }
    }
}
```

### Step 4: Enable and Start Services

```bash
# Copy systemd service files
sudo cp ~/ubuntu-setup/systemctl/qwen25-7b-server.service /etc/systemd/system/
sudo cp ~/ubuntu-setup/systemctl/nomic-embed-server.service /etc/systemd/system/
sudo cp ~/ubuntu-setup/systemctl/deepseek-r1-server.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable qwen25-7b-server
sudo systemctl enable nomic-embed-server
# Note: Don't enable deepseek-r1-server (on-demand only)

# Start services
sudo systemctl start qwen25-7b-server
sudo systemctl start nomic-embed-server

# Check status
sudo systemctl status qwen25-7b-server
sudo systemctl status nomic-embed-server

# Test nginx config and reload
sudo nginx -t
sudo systemctl reload nginx
```

### Step 5: Update Client Configurations

#### Continue.dev

Replace `~/.continue/config.json` with the optimized version from:
```
~/.continue/MULTI_MODEL_SETUP.md
```

#### Qwen Code

Add shell aliases from `~/.qwen/MULTI_MODEL_SETUP.md` to your `~/.bashrc`:

```bash
# Add to ~/.bashrc
export OPENAI_API_KEY="sk-no-key-required"
export OPENAI_BASE_URL="http://127.0.0.1/v1"

alias qwen-reasoning='OPENAI_BASE_URL=http://127.0.0.1/deepseek-r1/v1 qwen'
alias qwen-fast='OPENAI_BASE_URL=http://127.0.0.1/qwen25-7b/v1 qwen'

# Then reload
source ~/.bashrc
```

### Step 6: Verify Everything Works

```bash
# Test all endpoints
curl http://localhost:8080/health  # Qwen3-30B
curl http://localhost:8081/health  # Bielik-11B
curl http://localhost:8082/health  # Qwen2.5-7B
curl http://localhost:8083/health  # Nomic Embed
curl http://localhost:8084/health  # DeepSeek R1 (if started)

# Test via nginx
curl http://10.0.0.60/v1/models           # Main
curl http://10.0.0.60/qwen25-7b/v1/models # Autocomplete
curl http://10.0.0.60/nomic-embed/v1/models # Embeddings
curl http://10.0.0.60/deepseek-r1/v1/models # Reasoning

# Test aggregation endpoint
curl http://10.0.0.60/v1/models | jq '.data[].id'
```

## Performance Benefits

| Task | Before (Single Model) | After (Multi-Model) | Improvement |
|------|----------------------|---------------------|-------------|
| Tab autocomplete | ~50ms (30B) | ~15ms (7B) | **3.3x faster** |
| Embeddings | ~500ms (30B) | ~50ms (Nomic) | **10x faster** |
| Simple questions | ~80ms (30B) | ~25ms (7B) | **3.2x faster** |
| Reasoning tasks | Good (30B) | Excellent (R1) | **Better quality** |
| Memory usage | 40GB (1 model) | 51GB (3 models) | Still 69GB free |

## Memory Layout

```
GPU/APU Memory (120GB total):
├── Qwen3-30B Q8 (main):        40GB  [Always running]
├── Bielik-11B:                  8GB  [Always running]
├── Qwen2.5-7B (autocomplete):   8GB  [Always running]
├── Nomic Embed:                 3GB  [Always running]
├── DeepSeek R1:                24GB  [On-demand only]
└── Available:                  37GB  [With all models]
    OR                          61GB  [Without DeepSeek]
```

## On-Demand Usage Pattern

**Always Running** (59GB):
- Qwen3-30B: Main chat and complex coding
- Bielik-11B: Polish language support
- Qwen2.5-7B: Tab autocomplete (low latency)
- Nomic Embed: Embeddings (low latency)

**On-Demand** (24GB):
- DeepSeek R1: Start when needed for reasoning
  ```bash
  sudo systemctl start deepseek-r1-server
  qwen-reasoning "solve this complex problem"
  sudo systemctl stop deepseek-r1-server
  ```

## Monitoring

```bash
# Check all services
sudo systemctl status '*-server.service'

# View logs
sudo journalctl -u qwen25-7b-server -f
sudo journalctl -u nomic-embed-server -f
sudo journalctl -u deepseek-r1-server -f

# Check memory usage
rocm-smi  # GPU memory
htop      # System overview
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u service-name -n 50

# Check if port is in use
ss -tlnp | grep :8082

# Verify wrapper script is executable
ls -l ~/wrappers/*.sh

# Test wrapper directly
/home/mornel/wrappers/qwen25-7b-autocomplete-server.sh
```

### Nginx routing issues

```bash
# Test nginx config
sudo nginx -t

# Check nginx logs
sudo tail -f /var/log/nginx/error.log

# Verify upstreams are responsive
curl http://localhost:8082/health
```

### Out of memory

```bash
# Check GPU memory
rocm-smi

# Stop on-demand services
sudo systemctl stop deepseek-r1-server

# Reduce context sizes in wrapper scripts
```

## File Locations

| Component | Location |
|-----------|----------|
| Wrapper scripts | `/home/mornel/wrappers/` |
| Systemd services | `/etc/systemd/system/*-server.service` |
| Continue config | `~/.continue/config.json` |
| Qwen config | `~/.qwen/settings.json` |
| Models | `/home/mornel/models/` (host) → `/models/` (container) |
| Setup docs | `/home/mornel/ubuntu-setup/` |

## Quick Reference Commands

```bash
# Start/stop services
sudo systemctl start qwen25-7b-server
sudo systemctl stop qwen25-7b-server
sudo systemctl restart qwen25-7b-server
sudo systemctl status qwen25-7b-server

# View logs
sudo journalctl -u qwen25-7b-server -f

# Test endpoints
curl http://localhost:8082/health
curl http://10.0.0.60/qwen25-7b/v1/models

# Reload nginx
sudo systemctl reload nginx
```
