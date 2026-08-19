#!/bin/bash

# ==============================================================================
# Bielik-11B-v3.0-Instruct llama-server Configuration
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Model: Polish language model by SpeakLeash
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Create log directory
mkdir -p "$HOME/.local/log"
LOG_FILE="$HOME/.local/log/Bielik-11B-v3.0-Instruct.log"

# --- PINNED TO ROLLED-BACK llama.cpp BINARIES (2026-08-19) ----------------
# Build 666f8898a silently corrupts output on this hardware above ~1600 prompt
# tokens (mangled tokens, prompt regurgitation, KV bleed between unrelated
# requests). Root-caused 2026-08-19 to the binary itself: NOT KV quantization,
# NOT the new prompt cache, NOT context size. Both production models are pinned
# to 4d828bd1a, which is verified clean. See LLAMA_ISSUES_SUMMARY.md.
#
# The LD_LIBRARY_PATH prefix below is REQUIRED: without it this binary loads the
# newer libllama.so from build/bin and dies with `undefined symbol:
# llama_params_fit`, crash-looping the unit.
#
# Cost: ~15-20% generation speed. Re-test any future upstream build with the
# reproducer in LLAMA_ISSUES_SUMMARY.md BEFORE unpinning.
# --------------------------------------------------------------------------
ROLLBACK_BIN="/home/mornel/llama.cpp/bin-backup-4d828bd1a"
export LD_LIBRARY_PATH="${ROLLBACK_BIN}:/opt/rocm-7.2.4/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "${ROLLBACK_BIN}/llama-server" \
  \
  `# MODEL CONFIGURATION` \
  -m /home/mornel/models/Bielik-11B-v3.0-Instruct.Q8_0.gguf \
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
  -fa 1 \
  --no-mmap \
  \
  `# CONTEXT & MEMORY (Larger context possible with smaller model)` \
  -c 32768 \
  `# 32K total context. NOTE: -c is the TOTAL budget split across --parallel` \
  `# slots, so 32768/2 = 16K per slot - the same per-slot context as the` \
  `# previous "-c 65536 --parallel 4", at half the KV cache.` \
  --cache-reuse 2048 \
  `# KV cache reuse for efficiency` \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  `# Quantized KV (needs -fa 1, set above). Bielik is a DENSE 11B, so unlike` \
  `# Qwen3-Coder-Next's Gated-DeltaNet layers its KV cache is huge: it measured` \
  `# 12.5 GiB, larger than the 10.9 GiB of weights. Halving the total context` \
  `# and quantizing K/V takes that to ~3.2 GiB, freeing ~9 GiB on a box that` \
  `# runs at ~102/124 GB alongside Qwen + 4 VMs.` \
  \
  `# PARALLEL PROCESSING` \
  --parallel 2 \
  `# 2 slots - see the -c note above; per-slot context is unchanged at 16K` \
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
