#!/bin/bash

# ==============================================================================
# Qwen3-Coder-30B llama-server Configuration v4 (Continue.dev Optimized)
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Continue.dev IDE integration (autocomplete, chat, edits)
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/Qwen3-Coder-30B-A3B-Instruct-UD-Q8_K_XL.gguf \
  --alias Qwen3-Coder-30B-A3B-Instruct \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8080 \
  \
  `# TEMPLATE & REASONING` \
  --jinja \
  --reasoning-format deepseek \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY (Optimized for Continue.dev)` \
  -c 131072 \
  `# 64K context - optimal for IDE usage, faster processing` \
  --cache-reuse 2048 \
  `# KV cache reuse - critical for Continue's similar context pattern` \
  \
  `# PARALLEL PROCESSING (Optimized for Continue.dev)` \
  --parallel 4 \
  `# 4 slots: autocomplete + chat + slash commands + inline edits` \
  -sps 0.5 \
  `# Slot prompt similarity: reuse slots with 50%+ match` \
  -cb \
  `# Continuous batching` \
  -b 4096 \
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
  --no-webui

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

# ==============================================================================
