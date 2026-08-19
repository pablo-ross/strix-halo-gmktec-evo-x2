# LLaMA Server Issues Summary

## Issue: silent output corruption on llama.cpp `666f8898a` (2026-08-17 → 2026-08-19)

### Symptom
One bug with two very different faces, which is why it took two days to connect them.

**Loud (Qwen3-Coder-Next, 2026-08-17):** `//////////` for every prompt, at normal throughput,
no errors in the journal, no GPU faults in `dmesg`. Cleared by a restart.

**Quiet (Bielik-11B, noticed 2026-08-18):** normal-looking Polish with individual tokens mangled
— `Dwa plus dwa to cztefyry.` for `cztery` — degenerating on longer prompts into verbatim
regurgitation of the prompt and then repetition loops. Most damagingly, it leaked KV state from
*unrelated earlier requests*: text from a river-lengths validation prompt run on Aug 17 reappeared
verbatim inside completely unrelated wind-analysis generations on Aug 19.

Short prompts with short answers stayed clean throughout, on both models. That is why the loud
form looked like an isolated Qwen incident and Bielik was wrongly assumed to be a healthy control.

### Root Cause
The llama.cpp binary. `4d828bd1a` (2026-03-02) → `666f8898a` (2026-08-17), a 5.5-month
fast-forward taken for a +22% throughput gain. Nothing else.

**The trigger is prompt length**, not uptime, load, concurrency, or generation length:
clean below ~1600 prompt tokens, corrupt above. A 2940-token *generation* stayed completely clean,
which places the fault in prefill rather than decode.

### Ruled out by direct test
Each of these was applied to the live server, with a restart and a re-run of the reproducer:

| Hypothesis | Result |
|---|---|
| `--cache-type-k/v q8_0` (KV quantization, added Aug 17) | fails identically on `f16` |
| 8 GiB server-side prompt cache, new in this jump (`--cache-ram 0`) | fails identically |
| `-c 32768 --parallel 2` context change (Aug 17) | unrelated; corruption predates it in effect |
| Concurrency | reproduces on a single idle request |
| Memory pressure | PSI flat 0.00 at failure |
| The model file | unchanged since 2026-08-08; clean on the old binary |

Note the prompt cache is a real finding even though it was not the cause: disabling it **did** stop
the cross-request leakage. It explains how Aug 17 KV survived to Aug 19 (an 8 GiB LRU keyed by
prompt prefix, on by default, absent from the old build — the 2 slots could never have held it),
but the corruption itself is independent of it.

### Fix Applied
Both production wrappers pinned to the pre-update binaries:

```bash
ROLLBACK_BIN="/home/mornel/llama.cpp/bin-backup-4d828bd1a"
export LD_LIBRARY_PATH="${ROLLBACK_BIN}:/opt/rocm-7.2.4/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "${ROLLBACK_BIN}/llama-server" ...
```

**The `LD_LIBRARY_PATH` prefix is required, not cosmetic.** Without it the old binary resolves the
*new* `libllama.so` from `build/bin` and dies with `undefined symbol: llama_params_fit`, which
systemd turns into a crash loop.

Verification: the exact production payload that had been failing now returns output **byte-identical
to the last known-good response stored in the application DB (2026-08-16)**, 3/3, with a clean stop.

Cost: the +22% generation speed from the update is given up.

### Reproducer
Fails 3/3 on `666f8898a`, passes 3/3 on `4d828bd1a`. PASS = three clean Polish sentences;
FAIL = mangled words and/or a repetition loop.

```python
import json, urllib.request
filler = ("Kolarstwo szosowe to dyscyplina sportu rozgrywana na drogach asfaltowych. "
          "Zawodnicy pokonują dystanse od kilkudziesięciu do kilkuset kilometrów. ") * 30
body = {"model": "Bielik-11B-v3.0-Instruct", "max_tokens": 150, "temperature": 0.1,
        "messages": [{"role": "system", "content": "Jesteś asystentem. " + filler},
                     {"role": "user", "content": "Napisz jedno zdanie o kolarstwie."}]}
for i in range(3):
    req = urllib.request.Request("http://127.0.0.1:8081/v1/chat/completions",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=180))
    print(f"--- {i+1} ---"); print(d["choices"][0]["message"]["content"][:200])
```

### Lessons
1. **A throughput benchmark is not a correctness test.** The +22% measurement was real and was
   taken on a build that was already silently corrupting output.
2. **Health probes must be as long as the failure mode.** The original watchdog probe
   (`"List three colours."`) never fired once in 46 h against a provably broken server, because
   corruption needs ~1600+ prompt tokens to surface. A degeneracy heuristic (`≤3 distinct
   characters`) also cannot see `cztefyry`. The probe now sends ~2000 tokens and requires an exact
   answer; it was verified to fire 3/3 on the bad build and stay silent on the good one.
3. **Keep the binary backup.** `bin-backup-4d828bd1a` is the only reason this was a same-day fix
   rather than a rebuild-and-bisect exercise.

---

## Issue: llama-server crash after kernel 6.17.0-1012-oem update (2026-03-02)

### Symptom
`llama-server` segfaulting immediately on startup, consistently at offset `0xa8b3e` in
`libhsa-runtime64.so.1.18.0`, with `kfd_process_wq_release hogged CPU` warnings in `dmesg`.

### Root Cause
The old distrobox container (`kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma`) used
ROCm 7.0-rc userspace HSA runtime which was **incompatible with the KFD driver in kernel 6.17**.
The KFD kernel/userspace ABI changed between the 7.0-rc HSA runtime and kernel 6.17.

### Fix Applied

#### 1. ROCm 7.2 installed on host Ubuntu 24.04
- Updated `/etc/apt/sources.list.d/rocm.list` from `rocm/apt/7.1` → `rocm/apt/7.2`
- Installed: `rocm-hip-runtime-dev hipblas-dev`
- ROCm 7.2.0 now at `/opt/rocm-7.2.0/`

#### 2. llama.cpp rebuilt with correct Strix Halo flags
```bash
CC=/usr/bin/gcc CXX=/usr/bin/g++ cmake -S . -B build \
  -DGGML_HIP=ON \
  -DCMAKE_HIP_FLAGS="--rocm-path=/opt/rocm-7.2.0 -mllvm --amdgpu-unroll-threshold-local=600" \
  -DAMDGPU_TARGETS=gfx1151 \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_RPC=ON \
  -DROCM_PATH=/opt/rocm-7.2.0 \
  -DHIP_PLATFORM=amd
```
Key flags:
- `-mllvm --amdgpu-unroll-threshold-local=600` — performance regression workaround for ROCm 7+
- `-DAMDGPU_TARGETS=gfx1151` — Strix Halo (Radeon 8060S) target
- `LLAMA_HIP_UMA` is obsolete; UMA auto-detected at runtime for integrated GPUs

#### 3. Wrapper script updated (`~/wrappers/qwen3-coder-server.sh`)
- Removed `distrobox enter llama-rocm-7rc-rocwmma --` prefix (now runs natively)
- Added `export LD_LIBRARY_PATH="/opt/rocm-7.2.0/lib"`
- Added `-fa 1` (flash attention — **required** on Strix Halo, prevents crashes)
- Added `--no-mmap` (**required** on Strix Halo, prevents crashes/slowdowns)
- Fixed model path from `/models/` → `/home/mornel/models/`

#### 4. Systemd service updated
- `ExecStop` no longer references old distrobox container

### Runtime flags (from kyuz0/amd-strix-halo-toolboxes README)
Always use on Strix Halo:
- `-fa 1` — flash attention
- `--no-mmap` — prevents crashes and slowdowns
- `-ngl 999` — full GPU offload

### Hardware
- AMD Ryzen AI MAX+ 395 w/ Radeon 8060S (gfx1151 / Strix Halo)
- 115 613 MiB unified memory available to GPU

### Distrobox containers (no longer used for llama-server)
- `llama-rocm-7rc-rocwmma` — old, broken with kernel ≥ 6.17
- `llama-rocm-7.2` — new container created, has ROCm 7.2 runtime but no HIP compiler

### Reference
- https://github.com/kyuz0/amd-strix-halo-toolboxes — upstream Dockerfile and README
