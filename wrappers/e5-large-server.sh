#!/bin/bash

# ==============================================================================
# E5-Large-v2 Embedding Server
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: High-quality embeddings for RAG, semantic search
# Port: 8085
# Memory: ~2GB
# ==============================================================================

# NOTE: Model should be at ~/models/e5-large-F16.gguf
# Download from: https://huggingface.co/intfloat/e5-large-v2
# Convert to GGUF if needed

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/mornel/llama.cpp/build/bin/llama-server \
  \
  `# MODEL CONFIGURATION` \
  -m /models/e5-large-F16.gguf \
  --alias e5-large-v2 \
  \
  `# NETWORK` \
  --host 0.0.0.0 \
  --port 8085 \
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
  -c 512 \
  `# E5-Large uses 512 token context` \
  --cache-type-k f16 \
  --cache-type-v f16 \
  \
  `# PARALLEL PROCESSING - Reduced to maintain per-slot context` \
  --parallel 1 \
  `# Note: llama-server divides n_ctx by parallel slots` \
  `# With parallel=1: each request gets full 512 token context` \
  -cb \
  -b 512 \
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
# - E5-Large-v2 is a high-quality embedding model (335M parameters)
# - Competitive with much larger embedding models
# - Supports 512 token context window
# - Use for:
#   * High-precision semantic search
#   * RAG (Retrieval Augmented Generation)
#   * Document similarity
#   * Question answering systems
# - Smaller and faster than Nomic MoE, good for different use cases
