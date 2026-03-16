#!/bin/bash

# ==============================================================================
# Nomic Embed Text v2 MoE Server (DISABLED - Setup when ready)
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Fast embeddings for Continue.dev RAG, codebase search
# Port: 8083
# Memory: ~3GB
# ==============================================================================

# NOTE: First download the model:
# distrobox enter llama-rocm-7rc-rocwmma
# export HF_HUB_ENABLE_HF_TRANSFER=1
# hf download nomic-ai/nomic-embed-text-v2-moe-GGUF \
#   nomic-embed-text-v2-moe-f16.gguf \
#   --local-dir ~/models

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/mornel/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/nomic-embed-text-v2-moe.f16.gguf \
  --alias nomic-embed-text-v2-moe \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8083 \
  \
  `# EMBEDDING MODE` \
  --embeddings \
  `# Enable embeddings endpoint` \
  \
  `# GPU OFFLOADING` \
  -ngl 99 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY` \
  -c 8192 \
  `# 8K context - standard for embeddings` \
  --cache-type-k f16 \
  --cache-type-v f16 \
  \
  `# PARALLEL PROCESSING - High throughput for batch embeddings` \
  --parallel 16 \
  `# Many slots for batch embedding requests` \
  -cb \
  -b 2048 \
  -ub 512 \
  \
  `# CPU THREADING` \
  -t 8 \
  -tb 8 \
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
# - Nomic Embed is purpose-built for embeddings (not text generation)
# - 10x faster than using the 30B model for embeddings
# - Supports 100+ languages with 8K context
# - Use for:
#   * Codebase semantic search in Continue.dev
#   * RAG (Retrieval Augmented Generation)
#   * Finding similar code patterns
#   * Documentation search
