# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains setup guides and configuration documentation for optimizing Ubuntu 24.04 on the GMKTEC EVO-X2 (AMD Ryzen AI Max+ 395 with Radeon 8060S) for LLM inference using llama.cpp with ROCm 7 RC and rocWMMA.

## Hardware Context

**Target System:**
- CPU: AMD RYZEN AI MAX+ 395 w/ Radeon 8060S (32 threads)
- GPU: AMD Radeon Graphics (gfx1151, RDNA 3.5, 40 CUs, Strix Halo)
- RAM: 124 GiB system memory
- GPU Memory: 1 GB VRAM (framebuffer) + 128 GB GTT (unified compute memory)

**Critical Understanding:** For this APU, GTT (Graphics Translation Table) is the primary compute memory pool for LLM inference, not VRAM. The system has ~120GB available for inference workloads.

## Key Setup Steps Reference

### System Configuration (from ROADMAP.md)

**Kernel Requirements:**
- Minimum: Linux 6.16.9 (critical for >15GB VRAM access)
- Current: 6.17.0-1028-oem

**Note:** Kernel 6.17 broke the KFD kernel/userspace ABI against the ROCm 7.0-rc HSA runtime used by the old distrobox container below, causing `llama-server` to segfault in `libhsa-runtime64.so` (see `LLAMA_ISSUES_SUMMARY.md`). The fix was to move off distrobox and run ROCm 7.2 + llama.cpp natively on the host (see "Building and Running llama.cpp" below), which matches the host kernel's KFD ABI.

**Essential Kernel Parameters:**
```
amd_iommu=off amdgpu.gttsize=131072 ttm.pages_limit=31457280
```

**Critical Modprobe Configuration** (`/etc/modprobe.d/amdgpu_llm_optimized.conf`):
```bash
options amdgpu gttsize=122800
options ttm pages_limit=31457280
options ttm page_pool_size=31457280
```

**GPU Access (Ubuntu-specific):** Must create udev rules in `/etc/udev/rules.d/99-amd-kfd.rules`:
```bash
SUBSYSTEM=="kfd", GROUP="render", MODE="0666", OPTIONS+="last_rule"
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", GROUP="render", MODE="0666", OPTIONS+="last_rule"
SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", GROUP="render", MODE="0666", OPTIONS+="last_rule"
```
The `renderD[0-9]*` rule is critical - without it, ROCm will fail with `HSA_STATUS_ERROR_OUT_OF_RESOURCES`.

### Container Environment (legacy / initial setup path)

**Tool:** Distrobox (not toolbox - Ubuntu 24.04 doesn't include toolbox)
- Container: `docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma`
- Base OS: Fedora 44 (Rawhide)
- Package manager in container: `dnf` (not `apt`)

**Create container:**
```bash
distrobox create llama-rocm-7rc-rocwmma \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render --group-add wheel --security-opt seccomp=unconfined"
```

**Enter container:**
```bash
distrobox enter llama-rocm-7rc-rocwmma
```

**Note:** This container-based path is what the ROADMAP.md initial setup walkthrough uses, and still works for getting a first build running. However, the live system on this hardware has since moved off it (see "Native Host Build" below) because kernel 6.17 broke ABI compatibility with the container's bundled ROCm 7.0-rc runtime. If you hit `HSA_STATUS_ERROR_INVALID_PACKET_FORMAT` or similar HSA queue errors inside the container while the host works fine, this ABI mismatch is the likely cause — switch to the native host build.

### Building and Running llama.cpp (current production setup: native host, ROCm 7.2)

**Why native instead of distrobox:** ROCm 7.2 is installed directly on the host so the HSA runtime always matches the host kernel's KFD driver, avoiding the ABI-mismatch class of crash described above. See `LLAMA_ISSUES_SUMMARY.md` for the full incident writeup.

**Install ROCm 7.2 on host:**
```bash
# /etc/apt/sources.list.d/rocm.list should point at rocm/apt/7.2.4
sudo apt install rocm-hip-runtime-dev hipblas-dev
# Installs to /opt/rocm-7.2.4
```

**Location:** `~/llama.cpp` (native checkout, not inside a container)

**Build dependencies:**
```bash
sudo apt install -y cmake g++ git libcurl4-openssl-dev
```

**Build command:**
```bash
CC=/usr/bin/gcc CXX=/usr/bin/g++ cmake -S . -B build \
  -DGGML_HIP=ON \
  -DCMAKE_HIP_FLAGS="--rocm-path=/opt/rocm-7.2.4 -mllvm --amdgpu-unroll-threshold-local=600" \
  -DAMDGPU_TARGETS=gfx1151 \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_RPC=ON \
  -DROCM_PATH=/opt/rocm-7.2.4 \
  -DHIP_PLATFORM=amd

cmake --build build --config Release -j$(nproc)
```

Key flags:
- `-mllvm --amdgpu-unroll-threshold-local=600` — performance regression workaround needed on ROCm 7+
- `-DAMDGPU_TARGETS=gfx1151` — Strix Halo (Radeon 8060S) target
- `LLAMA_HIP_UMA` is obsolete; UMA is auto-detected at runtime for integrated GPUs

**Binaries location:** `build/bin/`

**Running:** set `LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"` before invoking `llama-server`/`llama-cli` (see `wrappers/*.sh` for real examples), and always pass `-fa 1` (flash attention) and `--no-mmap` — both are required on Strix Halo to avoid crashes/slowdowns.

### Running Inference

**Critical flags for this hardware:**
- `--no-mmap` (llama-cli) or `-mmp 0` (llama-bench): Required for GPU backends
- `-ngl 99` (or 999): Offload all layers to GPU
- `-fa 1`: Flash attention — required on Strix Halo, prevents crashes (added after the ROCm 7.2 migration; see `LLAMA_ISSUES_SUMMARY.md`)
- When running natively on the host (not distrobox), first: `export LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"`

**CLI inference:**
```bash
export LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"
./build/bin/llama-cli \
  -m ~/models/model.gguf \
  --no-mmap \
  -fa 1 \
  -ngl 99 \
  -p "prompt" \
  -n 128
```

**Benchmark:**
```bash
export LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"
./build/bin/llama-bench \
  -m ~/models/model.gguf \
  -mmp 0 \
  -fa 1 \
  -ngl 99 \
  -p 512 \
  -n 128
```

**Server mode:**
```bash
export LD_LIBRARY_PATH="/opt/rocm-7.2.4/lib"
./build/bin/llama-server \
  -m ~/models/model.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  -fa 1 \
  --no-mmap \
  -c 4096
```

See `wrappers/*.sh` for the actual production wrapper scripts used by the systemd services in this repo, which follow this same pattern per-model.

### Model Management

**Storage location:** `~/models` (persists across container/build updates)

**Downloading models:**
```bash
# Install HuggingFace CLI
pip install "huggingface-hub[cli]" hf-transfer

# Download (note: command is 'hf download' not 'huggingface-cli download')
export HF_HUB_ENABLE_HF_TRANSFER=1
hf download TheBloke/Llama-2-7B-GGUF llama-2-7b.Q4_K_M.gguf --local-dir ~/models
```

## Performance Characteristics

**Benchmark Results (from INITIAL_BENCHMARK.md):**
- Llama-2-7B Q4_K_M performance:
  - Prompt processing (512 tokens): 871.77 t/s
  - Text generation: 43.83 t/s
  - Optimal batch size: 512 tokens

**Memory Usage:**
- 7B Q4_K_M model: ~3.8 GB
- Context memory (4K): ~2 GB
- Total available: ~120 GB (can fit 70B+ models)

**Performance tuning:**
- Batch size: 512 (optimal for this hardware)
- Use `tuned-adm profile accelerator-performance`
- Verify GPU power state: check `/sys/class/drm/card1/device/power_dpm_force_performance_level`

## Common Issues and Solutions

### Ubuntu-Specific Issues

**`toolbox` not found:**
- Ubuntu 24.04 doesn't include `toolbox` in repos
- Use `distrobox` instead
- Replace all `toolbox` commands with `distrobox` commands

**`HSA_STATUS_ERROR_OUT_OF_RESOURCES` with rocminfo:**
- Missing renderD udev rule
- Fix: Add `renderD[0-9]*` rule to `/etc/udev/rules.d/99-amd-kfd.rules`
- Reload: `sudo udevadm control --reload-rules && sudo udevadm trigger`

**Container can't access GPU (legacy distrobox path):**
- Check permissions: `ls -la /dev/kfd /dev/dri/`
- All should be `0666` (crw-rw-rw-)
- Verify user in groups: `video` and `render`

**`HSA_STATUS_ERROR_INVALID_PACKET_FORMAT` / malformed AQL packet inside distrobox, but works on host:**
- KFD kernel/userspace ABI mismatch between host kernel and the container's bundled ROCm HSA runtime
- Fix: don't debug the container — switch to the native host build (see "Building and Running llama.cpp" above), which is the current production setup

### Build Issues in Container (legacy distrobox path)

**`cmake: command not found`:**
- Container doesn't include build tools by default
- Install: `sudo dnf install -y cmake gcc-c++ git libcurl-devel`

**Container uses `dnf` not `apt`:**
- ROCm container is Fedora-based
- Use `dnf` for package management

### llama.cpp Runtime Issues

**Invalid argument `--ngl`:**
- Use `-ngl` (single dash) not `--ngl` (double dash)

**`--no-mmap` invalid in llama-bench:**
- Use `-mmp 0` or `--mmap 0` instead
- `--no-mmap` only works with `llama-cli`

**`hf: command not found`:**
- HuggingFace CLI changed from `huggingface-cli` to `hf`
- Use `hf download` instead of `huggingface-cli download`

**Square brackets error in zsh:**
- Quote package name: `pip install "huggingface-hub[cli]"`

### General Performance Issues

**Only 15.5GB VRAM visible:**
- Upgrade kernel to 6.16.9+

**Slow model loading:**
- Add `--no-mmap` flag (CLI) or `-mmp 0` (bench)

**Poor performance:**
- Verify tuned profile: `tuned-adm active` should show `accelerator-performance`
- Check GPU power state (see above)

**Confused about VRAM vs GTT:**
- For APUs, GTT (128GB) is what matters for compute, not VRAM (1GB)
- This is normal and expected behavior

## Important Reminders

1. **Always use `--no-mmap`** with llama-cli on GPU backends
2. **Always use `-ngl 99`** to offload all layers to GPU
3. **Always use `-fa 1`** (flash attention) on Strix Halo to avoid crashes
4. **Store models in ~/models** (persists across builds/container updates)
5. **Never use Ollama** - lacks proper Vulkan/AMD support
6. **Kernel 6.16.9+ is critical** for >15GB VRAM access; kernel 6.17+ requires ROCm 7.2 (native host build) rather than the older ROCm 7.0-rc distrobox container, due to a KFD ABI break (see `LLAMA_ISSUES_SUMMARY.md`)
7. **`ROCBLAS_USE_HIPBLASLT=1`** was set by default in the kyuz0 distrobox containers; not currently exported anywhere in the native host setup (`wrappers/*.sh`), so don't assume it's set if running natively
8. **Optimal batch size is 512** for this hardware

## Verification Commands

**Check kernel:**
```bash
uname -r  # Should be 6.16.9 or later
```

**Check GPU memory:**
```bash
for file in /sys/class/drm/card*/device/mem_info*; do
  echo "$file: $(cat $file)";
done
```

**Check ROCm visibility:**
```bash
rocminfo | grep -A100 'Agent 2' | grep -A50 'Pool Info'
rocm-smi
```

**Check device permissions:**
```bash
ls -la /dev/kfd /dev/dri/renderD128  # Should be 0666
```

## Systemctl Configuration Files

The `systemctl/` directory contains production-ready systemd unit files, one per model currently served; `wrappers/` holds the matching launch scripts. Each wrapper execs `llama-server` natively (ROCm 7.2, see above) with model-specific flags on its own port.

**Current services (`systemctl/*.service` + `wrappers/*.sh`):**
- `llama-server.service` / `qwen3-coder-server.sh` - Qwen3-Coder-30B, port 8080, Continue.dev coding use
- `bielik-server.service` / `bielik-11b-server.sh`, `bielik-4.5b-server.sh` - Polish-language Bielik models, port 8081
- `deepseek-r1-server.service` / `deepseek-r1-reasoning-server.sh` - DeepSeek-R1 reasoning model
- `gpt-oss-server.service` / `gpt-oss-20b-server.sh` - GPT-OSS-20B
- `qwen25-7b-server.service` / `qwen25-7b-autocomplete-server.sh` - Qwen2.5-7B autocomplete
- `e5-large-server.service` / `e5-large-server.sh` - E5-Large-v2 embedding model
- `nomic-embed-server.service` / `nomic-embed-server.sh` - Nomic embedding model

**Key features (shared across wrappers):**
- Runs llama-server natively on the host (ROCm 7.2), not inside distrobox — see "Building and Running llama.cpp" above
- Automatic restart on failure
- Journal logging integration
- Each model on its own port so multiple can run concurrently (see `nginx/` for routing across them)

**Setup steps (per model):**
1. Copy the wrapper script to `~/wrappers/` and the matching `.service` file's `ExecStart` path should point at it
2. Update paths in both files (replace `mornel`/`username` with your actual username)
3. Make wrapper script executable: `chmod +x ~/wrappers/<script>.sh`
4. Copy service file to systemd: `sudo cp systemctl/<name>.service /etc/systemd/system/`
5. Enable and start: `sudo systemctl enable --now <name>`

## Server Deployment

**Systemd services for llama-server (see table above for the full current list):**
- See LLAMA.CPP_SERVER.md for detailed setup guide
- Enable with: `sudo systemctl enable --now <service-name>`
- Check status: `sudo systemctl status <service-name>`
- View logs: `sudo journalctl -u <service-name> -f`

**Firewall configuration:**
```bash
sudo ufw allow from 192.168.1.0/24 to any port 8080
```

**API compatibility:**
- llama-server implements OpenAI-compatible API
- Base URL: `http://SERVER_IP:8080/v1`
- Works with OpenAI Python library, Continue.dev, Cursor, etc.

## Additional Infrastructure

**`nginx/`** - OpenAI-compatible API gateway with dynamic model routing across all the per-model llama-server instances above (routes by the `"model"` field in the request body onto the right port). See `nginx/README.md` for setup.

**`docker-relay/`** - Dockerized relay (nginx + a small FastAPI app + `cloudflared`) for exposing local models to external clients through a Cloudflare Tunnel, without opening inbound ports on the router/firewall.

## Multi-Model Support

With 120GB memory, can run:
- Multiple 7B models simultaneously
- Single 70B+ model with large context
- 32K+ token context windows
- 4+ concurrent users with parallel requests

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **strix-halo-gmktec-evo-x2** (627 symbols, 635 relationships, 1 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/strix-halo-gmktec-evo-x2/context` | Codebase overview, check index freshness |
| `gitnexus://repo/strix-halo-gmktec-evo-x2/clusters` | All functional areas |
| `gitnexus://repo/strix-halo-gmktec-evo-x2/processes` | All execution flows |
| `gitnexus://repo/strix-halo-gmktec-evo-x2/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
