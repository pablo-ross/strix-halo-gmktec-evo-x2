# Qwen3.8-27B Evaluation — Considered, Rejected (Strix Halo / GMKTEC EVO-X2)

**Date:** August 17, 2026
**Question asked:** should production's coding model move from `Qwen3-Coder-Next` (80B-A3B) to `Qwen3.8-27B`, as packaged by [`julianmb/q38rocm`](https://github.com/julianmb/q38rocm)?
**Answer:** **no** — the model is excellent but is 3–4x slower to generate on this hardware, and the packaging around it (custom llama.cpp fork + fork-only quant format) buys nothing measurable here.
**Valuable side effect:** the investigation found `~/llama.cpp` was 5.5 months stale. Updating it gave production **+22% generation speed for free** (see [Engine update](#engine-update-the-actual-win) below).

---

## What was proposed

[`julianmb/q38rocm`](https://github.com/julianmb/q38rocm) packages `Qwen/Qwen3.8-27B` for exactly this hardware, claiming **30.56–36.04 tok/s** via three stacked mechanisms:

1. **`ROCmFP4` quantization** (4.26 bpw, 13.55 GiB) — a custom GGUF weight format from the [`charlie12345/ROCmFPX`](https://github.com/charlie12345/ROCmFPX) llama.cpp fork
2. **MTP speculative decoding** — using the model's built-in Multi-Token Prediction head as a self-draft
3. **Mesa RADV Wave64 cooperative matrices** — claiming Vulkan decode at ~36 t/s vs ~18.5 t/s on ROCm

The stack requires the ROCmFPX fork (pinned build `e87d53e`); stock `llama.cpp` cannot load `ROCmFP4` GGUFs. It also uses fork-only server flags (`-ctv turbo4`, `--spec-type draft-mtp`, `-cram`, `-ctxcp`).

**Everything referenced is real** — the model, the fork, the weights, the upstream repos all exist and the fork is actively developed (AMD-sponsored, 239 stars). This was checked before benchmarking; none of it is fabricated.

---

## The base model is genuinely strong

`Qwen/Qwen3.8-27B` (Alibaba Tongyi, released 2026-08-05):

- Dense 27B, **not** MoE — hybrid attention, 48 linear-attention + 16 full-attention layers, 64 total
- Multimodal (vision encoder), 262K native context, thinking-by-default
- SWE-bench Pro **61.7**, LiveCodeBench v6 **90.3**, Terminal Bench 2.1 **73.0**

On published coding benchmarks it is clearly ahead of `Qwen3-Coder-Next`. Quality was never the problem.

---

## Test setup

All numbers below measured on this box, same binary, same day.

- llama.cpp `666f8898a` (2026-08-17), built with the standard flags from CLAUDE.md
- ROCm 7.2.4 native host build, gfx1151
- A second Vulkan-only build (`-DGGML_VULKAN=ON -DGGML_HIP=OFF`, Mesa 25.2.8 RADV) for the backend comparison
- Weights: **official** `ggml-org/Qwen3.8-27B-GGUF` — `Qwen3.8-27B-Q4_K_M.gguf` (17.66 GiB) + `mtp-Qwen3.8-27B-Q8_0.gguf` (3.0 GiB draft head)
- Production llama-server (Qwen3-Coder-Next, port 8080) stopped during `llama-bench` runs so neither model competed for memory bandwidth

---

## Finding 1 — the custom fork is not needed

Stock upstream llama.cpp already covers the whole stack:

| Claimed as fork-exclusive | Reality on stock master |
|---|---|
| Loading Qwen3.8-27B | Arch `qwen35` is supported; loads and runs |
| MTP speculative decoding | Upstream since PRs #26177 … #27005 (Jul–Aug 2026), via `-md` + `--spec-draft-*` |
| Official quantized weights | `ggml-org/Qwen3.8-27B-GGUF` ships Q4_K_M/Q8_0 **and** the paired `mtp-*.gguf` head |

Adopting the fork would mean replacing the single `~/llama.cpp` build that **every** systemd service on this box shares — for capabilities upstream already has.

## Finding 2 — the Vulkan claim did not reproduce

The repo's headline is that RADV Wave64 coopmat delivers ~36 t/s decode where ROCm manages ~18.5 t/s. Built both backends and measured:

| Backend | pp512 | pp4096 | **tg128** |
|---|---:|---:|---:|
| ROCm (HIP) | 347.3 t/s | 332.7 t/s | **10.88 t/s** |
| Vulkan (RADV) | 288.1 t/s | 275.5 t/s | **11.06 t/s** |

**1.6% difference in decode**, and Vulkan is meaningfully *worse* at prefill.

This is the expected result, not a surprise: 17.66 GiB of weights at ~11 t/s implies ~208 GB/s of effective read bandwidth — already at the sustained ceiling of Strix Halo's 256-bit LPDDR5X bus. Decode here is memory-bandwidth bound. **No backend can beat that**; only shrinking the weights can.

## Finding 3 — MTP works, and is not enough

MTP self-speculation works on stock llama.cpp with the official `mtp-*.gguf` head. Measured under a controlled protocol — **1024 output tokens, temperature 0, 122-token prompt, `-fa 1 --no-mmap -c 8192 --parallel 1`, one server launch per configuration** (per-request speculative overrides are compiled out behind `#if 0` in `tools/server/server-schema.cpp`, so each config needs its own load):

**Q8_0 (26.6 GiB)**

| Config | Decode | vs off | Draft acceptance |
|---|---:|---:|---:|
| MTP off | 7.648 t/s | — | — |
| n-max 1, p-min 0.00 | 12.028 t/s | 1.57x | 74.3% |
| **n-max 3, p-min 0.00** | **13.097 t/s** | **1.71x** | 39.6% |
| n-max 3, p-min 0.60 | 11.514 t/s | 1.51x | 75.4% |
| n-max 6, p-min 0.60 | 11.861 t/s | 1.55x | 70.9% |

**Q4_K_M (17.66 GiB)**

| Config | Decode | vs off | Draft acceptance |
|---|---:|---:|---:|
| MTP off | 10.880 t/s | — | — |
| **n-max 3, p-min 0.00** | **14.271 t/s** | **1.31x** | 42.4% |
| n-max 6, p-min 0.60 | 13.865 t/s | 1.27x | 64.2% |

**MTP is worth 1.3–1.7x here, not more.** The gain is larger on the heavier quant, which is what the bandwidth model predicts: the more expensive each unassisted token is, the more a single multi-token verify pass saves.

### Counterintuitive: do not tune for acceptance rate

The default `--spec-draft-p-min 0.00` **beat** a conservative `0.60` gate in every pairing, despite roughly half the acceptance rate (39.6% vs 75.4%). Throughput tracks *tokens accepted per verify pass*, not the acceptance percentage — drafting aggressively and having most drafts rejected still beats drafting rarely with high precision, because the rejected tokens ride along in a verify pass that was going to happen anyway. A high acceptance rate mostly indicates the drafter is being too timid.

Practical setting on this hardware: **`--spec-type draft-mtp --spec-draft-n-max 3`, leaving `p-min` at its default**, with `-ngld 99` so the draft head is on the GPU.

> **Correction.** An earlier revision of this document reported "2.4x on code, 1.34x on prose, 76% acceptance" and recommended `p-min 0.60`. Those figures came from short (~300 token) generations against an already-warm server with prompt-cache reuse active, which inflated the rate; and the `p-min` recommendation was simply wrong, as the sweep above shows. The controlled numbers in this section supersede them. The conclusion of the evaluation is unaffected — it gets stronger, since MTP recovers less of the gap than first credited.

## Finding 4 — head-to-head, the incumbent wins on speed

Same build, same backend, production model vs candidate:

| | **Qwen3-Coder-Next** (current) | **Qwen3.8-27B** (candidate) |
|---|---:|---:|
| Architecture | 80B total / 3B active MoE | 27B dense, hybrid linear |
| Weights on disk | 46.2 GiB | 17.66 GiB (+3.0 MTP head) |
| pp512 | 346.2 t/s | 347.3 t/s |
| **pp4096** | **611.4 t/s** | 332.7 t/s |
| **tg128 (raw)** | **42.7 t/s** | 10.88 t/s |
| tg (best MTP config, 1024 tok) | 42.3 t/s | **14.3 t/s** |

The decisive factor is **active parameters**. Qwen3-Coder-Next moves ~3B active params per token; Qwen3.8-27B moves all 27B. On a bandwidth-bound APU that is a ~4x handicap, and MTP at 1.31x recovers only a small part of it — the candidate stays about **3x slower** even fully assisted.

Quality spot-check (fix an `asyncio` bug and explain it): both produced the correct fix. Qwen3.8's one-line explanation was slightly wrong on mechanism (claimed `.result()` "returns the task itself"; it actually raises `InvalidStateError`), Qwen3-Coder-Next's was accurate. A single prompt proves nothing about general quality — the benchmark scores above are the better evidence — but it does show the incumbent is not obviously outclassed on everyday work.

## Finding 5 — the best case for `ROCmFP4` still loses

`ROCmFP4` was not built and tested; the fork build plus a 14 GiB download wasn't justified once the ceiling was known. Its only real lever is size — 13.55 GiB vs 17.66 GiB, **−23%**. Since decode is purely bandwidth-bound here, that scales almost linearly:

- 10.88 x (17.66 / 13.55) → **~14.2 t/s unassisted** (matches the repo's own reported 14.02 t/s — their unassisted numbers look internally consistent and honest)
- x1.31 measured MTP gain at this quant level → **~18.6 t/s**

So the fully-optimized fork stack would land near **18.6 t/s against the incumbent's 42.3 t/s** — less than half. That projection is why the fork went untested; it would have to be wrong by more than 2x to change the decision.

Note this is where the corrected MTP figure bites hardest: the earlier revision projected ~33 t/s here off the inflated 2.4x, making the fork look like it might reach parity. It does not come close.

---

## Decision

**Stay on `Qwen3-Coder-Next`.** The trade on offer was:

| Give up | Get |
|---|---|
| **~66% decode speed** (42.3 → 14.3 t/s, MTP on) | Stronger coding benchmarks |
| ~45% prefill speed (611 → 333 t/s) | ~28 GB RAM freed |

Prefill matters disproportionately for Continue.dev, which ships large repo contexts on every request. And the RAM argument, while real — this box runs at ~100/124 GB with swap fully consumed alongside Bielik and 4 VMs — is not worth cutting the primary coding assistant to a third of its speed.

**Revisit if:** a coder-specialized Qwen3.8 lands (an A3B-style MoE at this quality would win outright), or memory pressure on this box becomes an actual failure rather than a nuisance.

---

## Engine update (the actual win)

`~/llama.cpp` was pinned at `4d828bd1a` (2026-03-02) — 5.5 months stale, and with no MTP support at all. Fast-forwarded to `666f8898a` (2026-08-17) and rebuilt with the unchanged flags from CLAUDE.md.

| Qwen3-Coder-Next on port 8080 | Before | After |
|---|---:|---:|
| Generation (live server, 3 runs) | 33–35 t/s | **42.2–42.3 t/s** |

**+22% on the model already in production**, from a rebuild alone — a larger real-world gain than the model swap would have delivered.

Verified after the update:

- `llama-server` (Qwen3-Coder-Next, :8080) — healthy, 42.2–42.3 t/s across 3 runs
- `bielik-server` (Bielik-11B-v3.0, :8081) — healthy, 17.6 t/s, Polish output correct
- Restarted one service at a time so both models stayed reachable
- nginx gateway end-to-end: `/v1/models` aggregates both backends, chat routing returns correctly from each

Rollback: previous binaries kept at `~/llama.cpp/bin-backup-4d828bd1a` (246 MB). Copy them back over `build/bin` and restart the units.

### Incidental finding: gateway is IPv4-only

`/etc/nginx/sites-enabled/llama-api` declares `listen 80;` with no `listen [::]:80;`. Requests to `http://localhost/...` resolve to `::1`, fall through to nginx's default server, and return **404**. Over `127.0.0.1` or the LAN IP everything works. Pre-existing, unrelated to this work — adding `listen [::]:80;` to that server block would fix it.

---

## Reproducing these numbers

```bash
export LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"
cd ~/llama.cpp

# Weights (official, stock-compatible — no fork needed)
export HF_HUB_ENABLE_HF_TRANSFER=1
hf download ggml-org/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-Q4_K_M.gguf mtp-Qwen3.8-27B-Q8_0.gguf --local-dir ~/models

# Raw throughput (stop the production server first — it needs the bandwidth)
./build/bin/llama-bench -m ~/models/Qwen3.8-27B-Q4_K_M.gguf \
  --load-mode direct -fa 1 -ngl 99 -p 512,4096 -n 128 -r 2

# With MTP self-speculation (best measured config — leave p-min at its 0.00 default)
./build/bin/llama-server -m ~/models/Qwen3.8-27B-Q4_K_M.gguf \
  -md ~/models/mtp-Qwen3.8-27B-Q8_0.gguf -ngld 99 \
  --spec-type draft-mtp --spec-draft-n-max 3 \
  -ngl 99 -fa 1 --no-mmap -c 8192 --parallel 1 --jinja --metrics --port 8090

# Acceptance rate:  curl -s localhost:8090/metrics | grep spec_decode
```

Measure with **1024 output tokens at temperature 0**. Short generations against a warm server overstate the MTP gain substantially — that is exactly how the superseded 2.4x figure arose. Prompt-cache reuse and per-request startup effects both flatter short runs.

Speculative parameters **cannot be swept per request**: the `speculative.n_max` / `p_min` / `type` request fields exist in `tools/server/server-schema.cpp` but the whole block sits behind `#if 0`. Each configuration needs its own server launch.

Note `-mmp 0` is deprecated on current master in favour of `--load-mode {mmap,direct}`; it still works but warns.

Qwen3.8-27B is thinking-by-default. For anything latency-sensitive, disable it — `"chat_template_kwargs": {"enable_thinking": false}` per request, or `--reasoning-budget 0` server-side, as `wrappers/qwen3-coder-server.sh` already does.

Building the Vulkan backend needs `glslc libvulkan-dev vulkan-tools spirv-headers glslang-tools spirv-tools` — CMake fails on missing `SPIRV-Headers` if only `glslc` is installed.

---

**Evaluation completed:** August 17, 2026
**Outcome:** model swap rejected; llama.cpp updated to `666f8898a`; production unchanged at `Qwen3-Coder-Next-UD-Q4_K_XL`, now 22% faster
**Revised:** August 17, 2026 — MTP figures replaced with controlled-protocol measurements (1.3–1.7x, not 2.4x) and the `p-min` recommendation reversed; see Finding 3
