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
LOG_FILE="$HOME/.local/log/gpt-oss-20b.log"

# Log startup
echo "[$(date)] Starting GPT-OSS-20B server..." >> "$LOG_FILE"
exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/mornel/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/gpt-oss-20b-F16.gguf \
  --alias gpt-oss-20b \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8086 \
  \
  `# TEMPLATE & REASONING` \
  --jinja \
  --reasoning-format none \
  --reasoning-budget 0 \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY` \
  -c 32768 \
  `# GPT-OSS native: 32K context window` \
  --n-predict 4096 \
  --cache-reuse 2048 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  \
  `# PARALLEL PROCESSING` \
  --parallel 4 \
  `# 4 slots for Continue.dev workflows` \
  -sps 0.5 \
  -cb \
  -b 2048 \
  -ub 512 \
  \
  `# CPU THREADING` \
  -t 16 \
  -tb 16 \
  \
  `# SAMPLING PARAMETERS (GPT-OSS optimized)` \
  --temp 0.7 \
  `# Slightly higher - GPT-OSS benefits from it` \
  --top-p 0.9 \
  `# Lower top-p for more focused outputs` \
  --top-k 40 \
  `# Standard for general models` \
  --min-p 0.05 \
  `# Higher min-p to filter low-prob tokens` \
  --repeat-penalty 1.1 \
  `# Slightly stronger penalty` \
  \
  `# SERVER OPTIONS` \
  --metrics \
  --no-webui \
  --no-warmup \
  \
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
