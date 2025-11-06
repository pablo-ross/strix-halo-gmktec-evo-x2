#!/bin/bash

# ==============================================================================
# DeepSeek-R1-Distill Reasoning Server (DISABLED - Setup when ready)
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Step-by-step reasoning, complex problem solving
# Port: 8084
# Memory: ~24GB
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/DeepSeek-R1-Distill-Qwen-32B-Q4_K_L.gguf \
  --alias DeepSeek-R1-Distill-Qwen-32B \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8084 \
  \
  `# TEMPLATE & REASONING` \
  --jinja \
  --reasoning-format deepseek \
  `# Enable DeepSeek reasoning mode` \
  --reasoning-budget 8192 \
  `# Allow up to 8K tokens for reasoning` \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY - Large for reasoning chains` \
  -c 131072 \
  `# 128K context for complex reasoning` \
  --cache-reuse 2048 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --kv-unified \
  \
  `# PARALLEL PROCESSING` \
  --parallel 2 \
  `# Fewer slots - reasoning is serial` \
  -sps 0.3 \
  -cb \
  -b 4096 \
  `# Larger batch for reasoning throughput` \
  -ub 1024 \
  \
  `# CPU THREADING` \
  -t 16 \
  `# More threads for reasoning` \
  -tb 16 \
  \
  `# SAMPLING PARAMETERS - Higher temp for creative reasoning` \
  --temp 0.7 \
  --top-p 0.95 \
  --top-k 40 \
  --min-p 0.05 \
  --repeat-penalty 1.1 \
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
# - DeepSeek R1 excels at step-by-step reasoning
# - --reasoning-format deepseek enables structured thinking
# - Large reasoning budget allows complex problem decomposition
# - Use this model when you need:
#   * Mathematical proofs
#   * Algorithm design
#   * Complex debugging
#   * Multi-step planning
