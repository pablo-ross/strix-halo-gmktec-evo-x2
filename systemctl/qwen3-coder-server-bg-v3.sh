#!/bin/bash

# ==============================================================================
# Qwen3-Coder-30B llama-server Configuration v3
# ==============================================================================
# Optimized for: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Based on: Unsloth Qwen3-Coder recommendations
# Reference: https://docs.unsloth.ai/models/qwen3-coder-how-to-run-locally
# ==============================================================================

# Wrapper script for llama-server in distrobox
# This script is needed because systemd can't execute distrobox enter directly

# Ensure XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Execute llama-server inside the distrobox container
exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  \
  `# ========================================================================` \
  `# MODEL CONFIGURATION` \
  `# ========================================================================` \
  \
  -m /home/username/models/Qwen3-Coder-30B-A3B-Instruct-UD-Q8_K_XL.gguf \
  `# Path to the quantized model file (Q8_K_XL = high quality 8-bit quant)` \
  \
  --alias Qwen3-Coder-30B-A3B-Instruct \
  `# Friendly name for the model in API responses` \
  \
  `# ========================================================================` \
  `# NETWORK CONFIGURATION` \
  `# ========================================================================` \
  \
  --host 0.0.0.0 \
  `# Listen on all network interfaces (allows LAN access)` \
  \
  --port 8080 \
  `# Server port for HTTP API (OpenAI-compatible)` \
  \
  `# ========================================================================` \
  `# TEMPLATE & REASONING` \
  `# ========================================================================` \
  \
  --jinja \
  `# Enable Jinja2 template support for chat formatting` \
  `# Uses model's native <|im_start|>/<|im_end|> format` \
  \
  --reasoning-format deepseek \
  `# Enable DeepSeek-style reasoning/thinking mode` \
  `# Model will show reasoning steps before final answer` \
  \
  `# ========================================================================` \
  `# GPU OFFLOADING` \
  `# ========================================================================` \
  \
  -ngl 99 \
  `# Number of GPU Layers: 99 = offload all layers to GPU` \
  `# Critical for performance on ROCm with 120GB GTT memory` \
  \
  --no-mmap \
  `# Disable memory mapping (required for GPU backends)` \
  `# Forces direct memory loading for better GPU performance` \
  \
  `# ========================================================================` \
  `# CONTEXT & MEMORY` \
  `# ========================================================================` \
  \
  -c 131072 \
  `# Context window size: 128K tokens` \
  `# Model supports up to 256K (native) or 1M (with YaRN)` \
  `# 128K is optimal balance for this hardware` \
  \
  `# ========================================================================` \
  `# PARALLEL PROCESSING` \
  `# ========================================================================` \
  \
  --parallel 2 \
  `# Number of parallel sequences to process` \
  `# Allows handling 2 concurrent requests` \
  `# Can increase to 4+ with 120GB memory available` \
  \
  -b 4096 \
  `# Batch size: tokens processed per iteration during prompt` \
  `# 2048 is optimal for Strix Halo based on benchmarks` \
  `# Higher = faster prompt processing but more memory` \
  \
  -ub 512 \
  `# Ubatch size: micro-batch for splitting large batches` \
  `# 512 is good default for memory efficiency` \
  \
  `# ========================================================================` \
  `# CPU THREADING` \
  `# ========================================================================` \
  \
  -t 16 \
  `# Threads for prompt processing (increased from 8)` \
  `# Ryzen AI Max+ 395 has 32 threads total` \
  `# 16 threads balances performance with system overhead` \
  \
  -tb 16 \
  `# Threads for batch/generation processing` \
  `# Keep at 16 for optimal generation performance` \
  \
  `# ========================================================================` \
  `# SAMPLING PARAMETERS (Qwen3 Official Recommendations)` \
  `# ========================================================================` \
  \
  --temp 0.6 \
  `# Temperature: 0.6 for thinking/reasoning mode` \
  `# Lower = more focused/deterministic (0.7 for non-thinking mode)` \
  `# WARNING: Never use 0.0 (greedy) - causes endless repetitions!` \
  `# Reference: Qwen team official recommendations` \
  \
  --top-p 0.95 \
  `# Top-P (nucleus sampling): 0.95 for thinking mode` \
  `# Higher than non-thinking mode (0.8) for better reasoning` \
  `# Keeps top 95% probability mass of tokens` \
  \
  --top-k 20 \
  `# Top-K sampling: Consider top 20 tokens` \
  `# Qwen team recommended value for all modes` \
  \
  --min-p 0.01 \
  `# Min-P: Minimum probability threshold (0.01)` \
  `# Qwen recommends 0.0-0.01 (llama.cpp default 0.1 is too high)` \
  `# Helps prevent low-quality token selection` \
  \
  --repeat-penalty 1.05 \
  `# Repetition penalty: 1.05 (Qwen official value)` \
  `# Slight penalty to prevent repetitive text` \
  `# Too high (>1.1) can hurt coherence` \
  \
  `# ========================================================================` \
  `# SERVER OPTIONS` \
  `# ========================================================================` \
  \
  --metrics \
  `# Enable Prometheus metrics endpoint at /metrics` \
  `# Useful for monitoring performance and usage` \
  \
  --no-webui
  `# Disable built-in web UI (optional)` \
  `# Remove this flag to enable simple web interface` \

# ==============================================================================
# ALTERNATIVE CONFIGURATIONS
# ==============================================================================

# NON-THINKING MODE (Standard Qwen3-Coder parameters):
# --temp 0.7         # Higher temperature for non-reasoning tasks
# --top-p 0.8        # Lower top-p for more focused responses
# --min-p 0.01       # Keep same as thinking mode

# CONSERVATIVE CONFIG (if experiencing OOM or instability):
# -c 65536           # 64K context (reduces memory usage)
# --parallel 1       # Single request at a time
# -b 1024            # Smaller batch size

# AGGRESSIVE CONFIG (maximize capabilities with 120GB memory):
# -c 262144          # Full 256K native context window
# --parallel 4       # Handle 4 concurrent requests
# --cache-type-k q4_1   # Better KV cache quality (slower)
# --cache-type-v q4_1

# MAXIMUM CONTEXT (requires YaRN):
# -c 1048576         # 1M tokens (requires --rope-scaling yarn)
# --rope-scaling yarn
# --rope-scale 4.0

# ==============================================================================
# PERFORMANCE NOTES
# ==============================================================================
# Expected performance (based on benchmarks):
# - Generation: ~71 tokens/second (with Q4_K_M, Q8 may be slightly slower)
# - Memory usage: ~18-24 GB for model + KV cache
# - Prompt processing: ~800-900 tokens/second
#
# MoE offloading (-ot flag) is CRITICAL:
# - Without it: May experience slowdowns as GPU swaps expert layers
# - With it: Significant speed improvement by keeping active layers on GPU
#
# Key memory pools on Strix Halo:
# - VRAM: 1 GB (framebuffer only)
# - GTT: 128 GB (primary compute memory - this is what matters!)
# - Available for inference: ~120 GB after OS overhead
# ==============================================================================
