#!/bin/bash

# ==============================================================================
# Qwen3-Coder-Next llama-server Configuration v5.0
# ==============================================================================
# Hardware: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (Strix Halo)
# Use Case: Continue.dev IDE integration (autocomplete, chat, edits)
# Changes: Swapped Qwen3-Coder-30B-A3B (dense attention) for Qwen3-Coder-Next
#          (80B total / 3B active, hybrid Gated-DeltaNet+attention MoE) at
#          UD-Q4_K_XL (~50GB) so it coexists with Bielik-11B + 3 running VMs
#          on this box's shared ~120GB GTT/RAM budget. Context trimmed from
#          200K to 128K for the same reason. The old model name still works
#          for existing clients via an alias rewrite in
#          docker-relay/app/main.py (see docker-relay/.env MODEL_ALIASES).
# ==============================================================================

# Wrapper for systemd - ensures XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Create log directory
mkdir -p "$HOME/.local/log"
LOG_FILE="$HOME/.local/log/qwen3-coder-server.log"

# Log startup
echo "[$(date)] Starting Qwen3-Coder-Next server..." >> "$LOG_FILE"

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
  -m /home/mornel/models/Qwen3-Coder-Next-UD-Q4_K_XL.gguf \
  --alias Qwen3-Coder-Next \
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
  -c 131072 \
  --n-predict 4096 \
  `# 128K context - trimmed from 200K to leave GTT headroom for Bielik + VMs` \
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
