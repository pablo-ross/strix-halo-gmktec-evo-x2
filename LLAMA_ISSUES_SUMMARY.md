# LLaMA Server Issues Summary

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
