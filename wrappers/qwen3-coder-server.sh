#!/bin/bash

# ==============================================================================
# Qwen3-Coder-30B llama-server Configuration v4.1 (Stability Optimized)
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Continue.dev IDE integration (autocomplete, chat, edits)
# Changes: Reduced to 64K context, removed kv-unified for stability
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Create log directory
mkdir -p "$HOME/.local/log"
LOG_FILE="$HOME/.local/log/qwen3-coder-server.log"

# Log startup
echo "[$(date)] Starting Qwen3-Coder server..." >> "$LOG_FILE"

export LD_LIBRARY_PATH="/opt/rocm-7.2.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec /home/username/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /home/username/models/Qwen3-Coder-30B-A3B-Instruct-UD-Q8_K_XL.gguf \
  --alias Qwen3-Coder-30B-A3B-Instruct \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8080 \
  \
  `# TEMPLATE & REASONING` \
  --jinja \
  --reasoning-format none \
  --reasoning-budget 0 \
  `# GPU OFFLOADING` \
  -ngl 99 \
  -fa 1 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY` \
  -c 200000 \
  --n-predict 4096 \
  `# 64K context - more stable, still enough for most coding tasks` \
  --cache-reuse 2048 \
  `# KV cache reuse - critical for Continue's similar context pattern` \
  --cache-type-k f16 \
  --cache-type-v f16 \
  \
  `# PARALLEL PROCESSING (Optimized for Continue.dev)` \
  --parallel 2 \
  `# 4 slots: autocomplete + chat + slash commands + inline edits` \
  -sps 0.5 \
  `# Slot prompt similarity: reuse slots with 50%+ match` \
  -cb \
  `# Continuous batching` \
  -b 2048 \
  `# Batch size: better for smaller, frequent requests` \
  -ub 512 \
  \
  `# CPU THREADING (Optimized for Continue.dev)` \
  -t 16 \
  `# 8 threads - lower overhead for frequent small prompts` \
  -tb 16 \
  \
  `# SAMPLING PARAMETERS (Qwen3 Official)` \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.01 \
  --repeat-penalty 1.05 \
  \
  `# SERVER OPTIONS` \
  --metrics \
  --no-webui \
  --no-warmup \
  `# ROCM OPTIONS` \
  --gpu-layers 99

# ==============================================================================
# ALTERNATIVE CONFIGURATIONS
# ==============================================================================

# NON-THINKING MODE:
# --temp 0.7 --top-p 0.8

# LARGER CONTEXT (if needed):
# -c 65536           # 64K context
# -t 12 -tb 12       # More threads for larger prompts

# MAXIMUM CONTEXT (standalone use):
# -c 131072          # 128K context
# --parallel 2       # Fewer slots for memory
# -b 4096            # Larger batch
# -t 16 -tb 16       # More threads
