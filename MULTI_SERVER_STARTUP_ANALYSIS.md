# Multi-Server Startup Analysis & Recommendations

## Current Implementation (Updated 2025-11-06)

**Decision**: Manual-start approach for all additional services.

**Configuration:**
- `llama-server.service` (Qwen3-30B): **ENABLED** - Auto-starts at boot
- `bielik-server.service` (Bielik-11B): **DISABLED** - Manual start only
- All future services: **DISABLED** - Manual start only

**Rationale:**
- Eliminates GPU race conditions at boot
- Faster boot time (single service initialization)
- No need for startup delay configurations
- Services can be started on-demand when needed

**Usage:**
```bash
# Start additional services when needed
sudo systemctl start bielik-server
sudo systemctl start qwen25-7b-server
sudo systemctl start nomic-embed-server

# Stop when not needed
sudo systemctl stop bielik-server
sudo systemctl stop qwen25-7b-server
```

---

## Problem Diagnosed (Historical Analysis)

### Root Cause: GPU Initialization Race Condition

When multiple llama-server instances start simultaneously on the same GPU (ROCm0), they compete for:

1. **GPU Memory Allocation** - Each model tries to reserve large chunks of VRAM/GTT
2. **ROCm Context Initialization** - ROCm can't handle multiple simultaneous init calls
3. **Model Loading** - Large models (30B) take ~10 seconds to load into GPU memory

### Evidence from Logs

**Qwen3-30B startup:**
```
llama_model_load: using device ROCm0 (0000:c4:00.0) - 116234 MiB free
Takes ~10 seconds to load 30B Q8 model
```

**Bielik-11B startup (with delay):**
```
llama_model_load: using device ROCm0 (0000:c4:00.0) - 122716 MiB free
Sees LESS free memory (because Qwen3 already loaded)
```

**Critical Finding**: Both services run in the SAME container and share the SAME GPU device.

### Why the 15-Second Delay Was Originally Added (Historical)

> **NOTE**: This delay has been **REMOVED** as of 2025-11-06. We now use manual startup instead.

The `startup-delay.conf` override previously added:
```ini
[Service]
ExecStartPre=/bin/sleep 15
```

This delay ensured:
- Qwen3-30B fully loads into GPU memory first (~10s)
- GPU resources are properly allocated before Bielik starts
- No ROCm initialization conflicts

### Historical Failures (Before Delay or Manual Start)

From `journalctl`:
```
- "unable to apply cgroup configuration"
- "Transaction for polkit.service/start is destructive"
- "dial unix /run/user/1000/bus: connect: connection refused"
- "Container Setup Failure!"
```

These were symptoms of the race condition. **Solution**: Manual startup eliminates the race condition entirely.

## Current Architecture

```
┌─────────────────────────────────────────────────┐
│  Ubuntu 24.04 Host                              │
│  ┌───────────────────────────────────────────┐  │
│  │  Distrobox Container (llama-rocm-7rc)    │  │
│  │                                           │  │
│  │  ┌──────────────────┐                    │  │
│  │  │  GPU (ROCm0)     │                    │  │
│  │  │  120GB GTT       │                    │  │
│  │  └────────┬─────────┘                    │  │
│  │           │                               │  │
│  │  ┌────────▼─────────────┐                │  │
│  │  │ llama-server (8080)  │ ← Qwen3-30B   │  │
│  │  │   40GB in use        │ (AUTO-START)   │  │
│  │  └──────────────────────┘                │  │
│  │                                           │  │
│  │  ┌──────────────────────┐                │  │
│  │  │ bielik-server (8081) │ ← Bielik-11B  │  │
│  │  │   8GB in use         │ (MANUAL START) │  │
│  │  └──────────────────────┘                │  │
│  │                                           │  │
│  │  Additional services available:          │  │
│  │  - qwen25-7b (8082) - manual             │  │
│  │  - nomic-embed (8083) - manual           │  │
│  │  - deepseek-r1 (8084) - manual           │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Memory Timeline During Startup

### Boot Sequence (Current Implementation)
```
Time    Service          GPU Memory      Status
──────────────────────────────────────────────────
0s      Boot             120GB free      System ready
0s      llama-server     Initializing    ROCm init (auto-start)
2s      llama-server     Loading model   116GB free
10s     llama-server     Ready           80GB free (40GB used)

        All other services: Not started (manual start only)
```

### Manual Start Sequence (When Needed)
```
Time    Service          GPU Memory      Status
──────────────────────────────────────────────────
0s      bielik-server    Starting        Manual: sudo systemctl start
2s      bielik-server    Initializing    ROCm init
5s      bielik-server    Loading model   80GB free
8s      bielik-server    Ready           72GB free (48GB total used)
```

## Recommendations for New Services

### Current Approach: Manual Start Only (IMPLEMENTED)

> **This is the approach we're currently using as of 2025-11-06.**

**Benefits:**
- ✅ Eliminates GPU race conditions entirely
- ✅ Faster boot time (only 10s for single service)
- ✅ No complex delay configurations needed
- ✅ Services started only when needed
- ✅ Easier troubleshooting

**Service Configuration:**
- `llama-server.service`: ENABLED (auto-starts)
- All other services: DISABLED (manual start)

**Usage:**

```bash
# Start services manually when needed
sudo systemctl start bielik-server        # Polish language model
sudo systemctl start qwen25-7b-server     # Fast autocomplete
sudo systemctl start nomic-embed-server   # Embeddings
sudo systemctl start deepseek-r1-server   # Reasoning tasks

# Check status
sudo systemctl status bielik-server

# Stop when not needed (frees GPU memory)
sudo systemctl stop bielik-server
sudo systemctl stop qwen25-7b-server
sudo systemctl stop nomic-embed-server
sudo systemctl stop deepseek-r1-server
```

---

## Alternative Approaches (Historical Reference)

These approaches were considered but **NOT implemented**. We chose manual startup instead.

### Option 1: Staggered Delays (Not Used)

Add fixed delays to prevent conflicts:
- llama-server: 0s (starts first)
- bielik-server: 15s delay
- qwen25-7b-server: 30s delay
- nomic-embed-server: 40s delay

**Why not used**: Slow boot time (~41s total), complex configuration.

### Option 2: Dependency Chains (Not Used)

Use systemd `After=` dependencies with short delays.

**Why not used**: "Started" doesn't mean "model loaded", unreliable timing.

## Memory Projections

### All Services Running (Worst Case)

```
Service             Model Size    Context    Total
──────────────────────────────────────────────────
llama-server        34GB         6GB        40GB
bielik-server       6GB          2GB        8GB
qwen25-7b-server    5GB          2GB        7GB
nomic-embed-server  2GB          1GB        3GB
──────────────────────────────────────────────────
TOTAL                                       58GB / 120GB
FREE                                        62GB
```

**Safe!** Plenty of room for all 4 servers.

### With DeepSeek (Maximum Load)

```
+ deepseek-r1-server  20GB       4GB        24GB
──────────────────────────────────────────────────
TOTAL                                       82GB / 120GB
FREE                                        38GB
```

**Still Safe!** But recommend on-demand use only.

## Systemd Service Dependencies

### Current Implementation

**llama-server.service (ENABLED):**
```ini
[Unit]
After=network.target user@1000.service
Requires=user@1000.service

[Service]
# Auto-starts at boot - no delays needed
```

**All other services (DISABLED for manual start):**
```ini
[Unit]
After=network.target user@1000.service
Requires=user@1000.service

[Service]
# NO ExecStartPre delays - manual start only
# NO auto-enable - started on demand
Restart=on-failure  # Will restart if crashes while running
```

**Key point**: With manual startup, no delays or dependency chains are needed. Services are started sequentially by the user when required.

## Testing Strategy

### Adding New Services (Manual Start Approach)

**For each new service:**

```bash
# 1. Install the service file
sudo cp ~/ubuntu-setup/systemctl/SERVICE_NAME.service /etc/systemd/system/
sudo systemctl daemon-reload

# 2. Test manual start
sudo systemctl start SERVICE_NAME

# 3. Watch logs in real-time
sudo journalctl -u SERVICE_NAME -f

# 4. Verify it works
curl http://localhost:PORT/health

# 5. Check GPU memory usage
distrobox enter llama-rocm-7rc-rocwmma -- rocm-smi

# 6. Test stop
sudo systemctl stop SERVICE_NAME

# 7. DO NOT enable auto-start (unless it's the primary service)
# We keep services disabled for manual startup
```

### Example: Testing qwen25-7b-server

```bash
sudo cp ~/ubuntu-setup/systemctl/qwen25-7b-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start qwen25-7b-server
sudo journalctl -u qwen25-7b-server -f
curl http://localhost:8082/health
```

### Example: Testing Multiple Services Together

```bash
# Start services one by one
sudo systemctl start bielik-server
curl http://localhost:8081/health

sudo systemctl start qwen25-7b-server
curl http://localhost:8082/health

sudo systemctl start nomic-embed-server
curl http://localhost:8083/health

# Check total memory usage
distrobox enter llama-rocm-7rc-rocwmma -- rocm-smi

# Stop all when done
sudo systemctl stop bielik-server qwen25-7b-server nomic-embed-server
```

## Troubleshooting

### If New Service Fails to Start

1. **Check if GPU is busy:**
   ```bash
   distrobox enter llama-rocm-7rc-rocwmma -- rocm-smi
   ```
   If another model is loading, wait for it to finish.

2. **Check logs for ROCm errors:**
   ```bash
   sudo journalctl -u SERVICE_NAME | grep -i "rocm\|error\|fail"
   ```

3. **Verify model file exists:**
   ```bash
   ls -lh ~/models/MODEL_FILE.gguf
   ```

4. **Check available memory:**
   ```bash
   curl http://localhost:8080/health  # Check if main server is running
   distrobox enter llama-rocm-7rc-rocwmma -- rocm-smi
   ```

5. **Restart the service:**
   ```bash
   sudo systemctl restart SERVICE_NAME
   sudo journalctl -u SERVICE_NAME -f
   ```

### Boot Time (Current Configuration)

With manual-start approach:
- Boot time: ~10 seconds (llama-server only)
- Other services: Started on-demand, no impact on boot

**This is much faster than the 41-second boot with auto-start for all services!**

## Monitoring Commands

```bash
# Check all llama-servers
systemctl status '*-server.service'

# Watch startup in real-time
journalctl -f -u llama-server -u bielik-server -u qwen25-7b-server -u nomic-embed-server

# Check which services are enabled
systemctl list-unit-files | grep server

# Check boot timeline
systemd-analyze critical-chain llama-server.service
systemd-analyze critical-chain bielik-server.service
```

## Implementation Plan (COMPLETED 2025-11-06)

### ✅ Phase 1: Configure Manual Start
1. ✅ Keep only llama-server.service enabled
2. ✅ Disable bielik-server.service auto-start
3. ✅ Remove startup-delay.conf overrides
4. ✅ Update documentation

### Phase 2: Add Additional Services (When Ready)
1. Install service files to /etc/systemd/system/
2. Test manual start for each service
3. Keep all services disabled (manual start only)
4. Document which services to start for different use cases

### Phase 3: Usage Patterns
Define when to start each service:
- **llama-server**: Always running (auto-start)
- **bielik-server**: Start for Polish language tasks
- **qwen25-7b-server**: Start for fast autocomplete (Continue.dev)
- **nomic-embed-server**: Start for embeddings/RAG tasks
- **deepseek-r1-server**: Start for complex reasoning tasks

## Summary

✅ **Implemented**: Manual-start approach (as of 2025-11-06)
✅ **Safe**: 58GB used / 120GB available with all services
✅ **Fast Boot**: ~10 seconds (single service only)
✅ **No Race Conditions**: Manual startup eliminates GPU conflicts
✅ **Flexible**: Start only the services you need
✅ **Simple**: No complex delay configurations needed

**Current Configuration:**
- Auto-start: llama-server.service only
- Manual-start: All other services
- No startup delays needed
