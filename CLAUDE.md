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
- Current: 6.16.9-061609-generic

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

### Container Environment

**Tool:** Distrobox (not toolbox - Ubuntu 24.04 doesn't include toolbox)
- Container: `docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma`
- Base OS: Fedora 44 (Rawhide)
- Package manager in container: `dnf` (not `apt`)

**Create container:**
```bash
distrobox create llama-rocm-7rc-rocwmma \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render --group-add sudo --security-opt seccomp=unconfined"
```

**Enter container:**
```bash
distrobox enter llama-rocm-7rc-rocwmma
```

### Building llama.cpp

**Location:** Inside the ROCm container at `~/llama.cpp`

**Build dependencies (install in container first):**
```bash
sudo dnf install -y cmake gcc-c++ git libcurl-devel python3-pip
```

**Build command:**
```bash
cmake -B build -S . \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS="gfx1151" \
  -DGGML_HIP_ROCWMMA_FATTN=ON \
  -DGGML_HIP_MMQ_MFMA=ON

cmake --build build --config Release -j$(nproc)
```

**Binaries location:** `build/bin/`

### Running Inference

**Critical flags for this hardware:**
- `--no-mmap` (llama-cli) or `-mmp 0` (llama-bench): Required for GPU backends
- `-ngl 99` (or 999): Offload all layers to GPU

**CLI inference:**
```bash
./build/bin/llama-cli \
  -m ~/models/model.gguf \
  --no-mmap \
  -ngl 99 \
  -p "prompt" \
  -n 128
```

**Benchmark:**
```bash
./build/bin/llama-bench \
  -m ~/models/model.gguf \
  -mmp 0 \
  -ngl 99 \
  -p 512 \
  -n 128
```

**Server mode:**
```bash
./build/bin/llama-server \
  -m ~/models/model.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 4096
```

### Model Management

**Storage location:** `~/models` (outside containers to persist across updates)

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

**Container can't access GPU:**
- Check permissions: `ls -la /dev/kfd /dev/dri/`
- All should be `0666` (crw-rw-rw-)
- Verify user in groups: `video` and `render`

### Build Issues in Container

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
3. **Store models in ~/models** (outside containers)
4. **Never use Ollama** - lacks proper Vulkan/AMD support
5. **Kernel 6.16.9+ is critical** for >15GB VRAM access
6. **Set `ROCBLAS_USE_HIPBLASLT=1`** (already set in kyuz0 containers)
7. **Optimal batch size is 512** for this hardware

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

**Check ROCm visibility (in container):**
```bash
rocminfo | grep -A100 'Agent 2' | grep -A50 'Pool Info'
rocm-smi
```

**Check device permissions:**
```bash
ls -la /dev/kfd /dev/dri/renderD128  # Should be 0666
```

## Systemctl Configuration Files

The `systemctl/` directory contains production-ready systemd service configuration for running llama-server as a system service.

**Files:**
- `llama-server.service` - Systemd unit file for llama-server service
- `qwen3-coder-server.sh` - Optimized wrapper script for Qwen3-Coder-30B

**Key features:**
- Runs llama-server inside distrobox container
- Automatic restart on failure
- Proper process management and cleanup
- Journal logging integration
- Pre-configured for 128K context window with DeepSeek-style reasoning

**Setup steps:**
1. Copy wrapper script to a suitable location (e.g., `~/wrappers/`)
2. Update paths in both files (replace `username` with your actual username)
3. Make wrapper script executable: `chmod +x ~/wrappers/qwen3-coder-server.sh`
4. Copy service file to systemd: `sudo cp systemctl/llama-server.service /etc/systemd/system/`
5. Enable and start: `sudo systemctl enable --now llama-server`

**The wrapper script includes:**
- Optimized parameters for Strix Halo hardware
- 128K context window support (-c 131072)
- DeepSeek-style reasoning mode (--reasoning-format deepseek)
- Qwen3 official sampling parameters (temp 0.6, top-p 0.95, top-k 20)
- Parallel request handling (--parallel 2)
- Comprehensive inline documentation

## Server Deployment

**Systemd service for llama-server:**
- Production-ready service file available in `systemctl/llama-server.service`
- Optimized wrapper script available in `systemctl/qwen3-coder-server.sh`
- See LLAMA.CPP_SERVER.md for detailed setup guide
- Enable with: `sudo systemctl enable --now llama-server`
- Check status: `sudo systemctl status llama-server`
- View logs: `sudo journalctl -u llama-server -f`

**Firewall configuration:**
```bash
sudo ufw allow from 192.168.1.0/24 to any port 8080
```

**API compatibility:**
- llama-server implements OpenAI-compatible API
- Base URL: `http://SERVER_IP:8080/v1`
- Works with OpenAI Python library, Continue.dev, Cursor, etc.

## Multi-Model Support

With 120GB memory, can run:
- Multiple 7B models simultaneously
- Single 70B+ model with large context
- 32K+ token context windows
- 4+ concurrent users with parallel requests
