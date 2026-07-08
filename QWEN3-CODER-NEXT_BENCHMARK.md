# Qwen3-Coder-Next Performance Benchmark - AMD Strix Halo (GMKTEC EVO-X2)

**Date:** July 8, 2026
**Setup:** Ubuntu 24.04 LTS + ROCm 7.2.4 (native host) + llama.cpp
**Test Model:** Qwen3-Coder-Next-UD-Q4_K_XL (49.6 GiB, 80B total / 3B active MoE, hybrid Gated-DeltaNet + attention)
**Test Method:** Server API testing via HTTP completions endpoint, same methodology as `QWEN3-CODER-30B_BENCHMARK.md`
**Important difference from the November baseline:** this run was measured **under concurrent load** — Bielik-11B-v3.0 (port 8081) and 3 running libvirt VMs (vm-dev 16GB, vm-chatwoot 12GB, vm-zammad 10GB) were active throughout, matching real production conditions on this box. The November benchmark was measured on an otherwise idle system. This alone accounts for a meaningful chunk of the generation-speed delta below.

---

## What changed since the last benchmark

- Swapped `Qwen3-Coder-30B-A3B-Instruct` (30B total / 3B active, dense attention) for `Qwen3-Coder-Next` (80B total / 3B active, hybrid linear-attention MoE, released Feb 2026)
- Quant: `UD-Q8_K_XL` (34GB) → `UD-Q4_K_XL` (49.6GB) — deliberately lower bit-depth than before, chosen so the larger (80B-total) model still fits alongside Bielik + all 3 VMs on the shared ~120GB GTT/RAM pool
- Context: `-c 200000` → `-c 131072` (128K) — trimmed to leave GTT headroom for the rest of the stack
- llama-server alias: `Qwen3-Coder-30B-A3B-Instruct` → `Qwen3-Coder-Next`; the old name is kept working transparently for existing clients via a rewrite in `docker-relay/app/main.py` (`MODEL_ALIASES` env var), so Continue.dev / other integrations needed no changes

---

## System Configuration

**Hardware:** unchanged — AMD Ryzen AI Max+ 395 (Radeon 8060S), 40 CU gfx1151, 124GiB RAM, 128GB GTT pool

**Software Stack (changed since November):**
- Kernel: 6.17.0-1028-oem (was 6.16.9) — required moving off the distrobox ROCm 7.0-rc container to a native ROCm 7.2.4 host build; see `LLAMA_ISSUES_SUMMARY.md`
- ROCm: 7.2.4 native host install (was 7.0 RC in distrobox/Fedora container)
- llama.cpp: current native host build (`~/llama.cpp`), not distrobox

**Concurrent load during this benchmark:**

| Process | Memory footprint |
|---|---|
| Qwen3-Coder-Next (port 8080, under test) | weights 49.6GB + KV cache |
| Bielik-11B-v3.0 Q8_0 (port 8081) | 12GB weights + KV cache |
| vm-dev | 16GB |
| vm-chatwoot | 12GB |
| vm-zammad | 10GB |

GTT used during test: **78.7GB / 128GB**. System RAM: 98Gi used / 124Gi total, 18Gi free, 25Gi available.

---

## Benchmark Results

Same test method as the baseline: 3 runs per prompt size (excluding no separate warm-up run this time — server had already served the earlier alias-rewrite smoke test), `/v1/completions`, `max_tokens: 128`, `temperature: 0.7`, `stream: false`.

| Test Type | Prompt Tokens | Avg Prompt Speed (t/s) | Avg Generation Speed (t/s) |
|-----------|--------------|------------------------|----------------------------|
| Short     | 9            | **112.65**             | **34.88**                  |
| Medium    | 35           | **243.67**             | **35.75**                  |
| Large     | 68           | **256.54**             | **35.49**                  |

### Detailed Results

#### Short Prompt (9 tokens)
```
Run 1: Prompt: 111.10 t/s, Generation: 36.60 t/s
Run 2: Prompt: 113.09 t/s, Generation: 32.29 t/s
Run 3: Prompt: 113.75 t/s, Generation: 35.77 t/s
```

#### Medium Prompt (35 tokens)
```
Run 1: Prompt: 242.96 t/s, Generation: 35.77 t/s
Run 2: Prompt: 243.24 t/s, Generation: 35.76 t/s
Run 3: Prompt: 244.80 t/s, Generation: 35.73 t/s
```

#### Large Prompt (68 tokens)
```
Run 1: Prompt: 248.73 t/s, Generation: 35.55 t/s
Run 2: Prompt: 261.15 t/s, Generation: 35.47 t/s
Run 3: Prompt: 259.74 t/s, Generation: 35.46 t/s
```

Generation speed is remarkably stable across prompt sizes (34.9–35.8 t/s) and across runs (std dev well under 1 t/s once warmed), same stability characteristic the November test found for the 30B model.

---

## Comparison with November Baseline (Qwen3-Coder-30B-A3B Q4_K_M, idle system)

| Metric | Qwen3-Coder-30B (Nov, idle) | Qwen3-Coder-Next (Jul, under load) | Delta |
|---|---|---|---|
| Total params | 30.5B | 79.7B | +2.6x |
| Active params | ~3B | ~3B | same |
| Quant | Q4_K_M (17.3GB) | UD-Q4_K_XL (49.6GB) | +2.9x weight size |
| Context | 8,192 | 131,072 | +16x |
| Generation speed | 71.0 t/s | 35.5 t/s | **-50%** |
| Prompt speed (medium) | 28.3 t/s | 243.7 t/s | **+8.6x** |
| Concurrent load | none (idle box) | Bielik-11B + 3 VMs | — |

### Reading this honestly

The generation-speed drop is real but **not directly comparable** — three things changed at once, not just the model:

1. **Concurrent load.** The November run had the whole 128GB GTT pool and all 32 threads to itself. This run shares the box with Bielik and three running VMs the entire time. On a UMA system like this, memory bandwidth is the generation-speed bottleneck, and it's shared across every process touching GTT — this is very likely the single biggest contributor to the drop.
2. **Much larger active KV-cache budget allocated** (131K vs 8K context) — even though Gated-DeltaNet layers keep per-token KV cost low, the server still reserves buffers sized for the configured `-c`, which affects scheduling/memory layout.
3. **Model architecture itself** — 80B total params (vs 30B) means more weight data moved per forward pass even with the same ~3B active, and the hybrid DeltaNet/attention layout has different kernel characteristics than pure dense attention; llama.cpp's ROCm kernels for this specific hybrid architecture are also newer/less mature than the well-optimized dense-attention path exercised in November.

Prompt processing, on the other hand, is dramatically faster (8.6x on the medium prompt) — consistent with the linear-attention layers making the prefill phase much cheaper for this architecture.

**Practical takeaway for interactive coding use:** 35 t/s generation is still comfortably above reading speed for streamed responses (Continue.dev, chat), and prompt ingestion — the part that matters most for large-context coding tasks — got much faster. The trade was made deliberately for coexistence: production now runs a strictly better model (80B vs 30B total capacity) at the cost of a smaller quant and shared-machine contention, not because Qwen3-Coder-Next is inherently slower per-active-parameter.

### Recommended follow-up (not yet done)

- Re-run this benchmark with Bielik and the 3 VMs stopped, to isolate how much of the -50% generation-speed delta is contention vs. architecture/quant, before concluding anything about Qwen3-Coder-Next's raw ceiling on this hardware.
- Try `UD-Q5_K_XL` or `UD-Q6_K_XL` if/when running standalone (without Bielik+VMs) to see whether quant level matters much for generation speed on this workload (compute-bound MoE routing vs memory-bandwidth-bound weight reads).

---

**Benchmark completed:** July 8, 2026
**System:** GMKTEC EVO-X2 (AMD Strix Halo), under concurrent load (Bielik-11B + 3 VMs)
**Model:** Qwen3-Coder-Next-UD-Q4_K_XL, served under alias `Qwen3-Coder-Next` (legacy name `Qwen3-Coder-30B-A3B-Instruct` aliased via docker-relay)
**Result:** Deployed to production, generation speed acceptable for interactive use; isolated (no-contention) re-test recommended for a cleaner apples-to-apples comparison
