#!/bin/bash

# ==============================================================================
# Qwen2.5-Coder-7B Autocomplete Server (DISABLED - Setup when ready)
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Fast autocomplete for Continue.dev
# Port: 8082
# Memory: ~8GB
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/qwen2.5-coder-7b-instruct-q5_k_m.gguf \
  --alias qwen2.5-coder-7b-instruct \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8082 \
  \
  `# TEMPLATE & REASONING` \
  --jinja \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY - Optimized for fast autocomplete` \
  -c 16384 \
  `# 16K context - plenty for autocomplete` \
  --cache-reuse 1024 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --kv-unified \
  \
  `# PARALLEL PROCESSING - High throughput for autocomplete` \
  --parallel 8 \
  `# 8 slots for multiple simultaneous autocomplete requests` \
  -sps 0.7 \
  `# Higher slot reuse for similar autocomplete contexts` \
  -cb \
  `# Continuous batching` \
  -b 512 \
  `# Smaller batch for lower latency` \
  -ub 256 \
  \
  `# CPU THREADING - Optimized for speed` \
  -t 8 \
  `# Fewer threads for faster startup` \
  -tb 8 \
  \
  `# SAMPLING PARAMETERS - Low temperature for consistent autocomplete` \
  --temp 0.2 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.01 \
  --repeat-penalty 1.05 \
  \
  `# SERVER OPTIONS` \
  --metrics \
  --no-webui \
  --no-warmup \
  \
  `# ROCM OPTIONS` \
  --gpu-layers 99

# ==============================================================================
# NOTES
# ==============================================================================
# - This 7B model is 3-4x faster than the 30B for autocomplete
# - Lower context (16K) reduces memory and increases speed
# - High parallel slots (8) handles burst autocomplete requests
# - Low temperature (0.2) gives more deterministic completions
