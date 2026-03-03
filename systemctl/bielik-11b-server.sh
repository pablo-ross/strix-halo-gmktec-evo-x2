#!/bin/bash

# ==============================================================================
# Bielik-11B-v3.0-Instruct llama-server Configuration
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Model: Polish language model by SpeakLeash
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/Bielik-11B-v3.0-Instruct.Q8_0.gguf \
  --alias Bielik-11B-v3.0-Instruct \
  \
  `# NETWORK (Different port from Qwen3)` \
  --host 0.0.0.0 \
  --port 8081 \
  \
  `# TEMPLATE (ChatML format)` \
  --jinja \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY (Larger context possible with smaller model)` \
  -c 65536 \
  `# 64K context - plenty for 11B model` \
  --cache-reuse 2048 \
  `# KV cache reuse for efficiency` \
  \
  `# PARALLEL PROCESSING (More slots possible with smaller model)` \
  --parallel 4 \
  `# 4 slots - Q8_0 quantization uses ~2x memory vs Q4_K_M` \
  -sps 0.5 \
  `# Slot prompt similarity` \
  -cb \
  `# Continuous batching` \
  -b 4096 \
  `# Batch size` \
  -ub 512 \
  \
  `# CPU THREADING` \
  -t 16 \
  -tb 16 \
  \
  `# SAMPLING PARAMETERS (Bielik recommended)` \
  --temp 0.2 \
  `# Low temperature for deterministic responses per docs` \
  --top-p 0.95 \
  --top-k 40 \
  --min-p 0.01 \
  --repeat-penalty 1.05 \
  \
  `# SERVER OPTIONS` \
  --metrics \
  --no-webui

# ==============================================================================
# MODEL NOTES
# ==============================================================================
# - Bielik is a Polish language model (11B parameters)
# - Uses ChatML format (<|im_start|>, <|im_end|>)
# - Recommended temp=0.2 for focused responses
# - No moderation mechanisms - can produce biased/incorrect outputs
# - Q8_0 quantization (~11GB) for near-lossless quality
#
# MEMORY USAGE:
# - Model: ~11GB (Q8_0)
# - Context (64K): ~8GB
# - Total: ~19GB (plenty of room on 120GB system)
# ==============================================================================
