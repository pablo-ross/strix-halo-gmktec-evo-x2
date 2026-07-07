# Optimal Ubuntu 24.04 Setup Roadmap for GMKTEC EVO-X2 (Ryzen AI Max+ 395)

Based on your research, here's the step-by-step roadmap optimized for ROCm 7 RC with rocWMMA and hipBLASlt:

## Phase 1: BIOS Configuration (BEFORE OS Installation)

**Step 1.1: Configure GPU Memory**
- Set GART (Graphics Aperture Remapping Table) / UMA Frame Buffer Size as **low as your BIOS allows** (512MB on some boards/BIOS versions)
- Navigate to: Integrated Graphics → UMA Frame Buffer Size → lowest available value
- If available: Device Manager → AMD CBS → NBIO Common Options → GFX Configuration → Set as needed

**NOTE:** This BIOS setting only reserves a small, fixed dedicated VRAM framebuffer — it is unrelated to the ~120GB of GTT (unified compute memory) that this roadmap configures later via kernel/modprobe parameters (Phase 3). Some BIOS versions (e.g. EVO-X2 1.12) only expose 2GB as the minimum under `UMA_SPECIFIED`/`AUTO` instead of 512MB. **This is fine** — just pick the lowest value offered (2GB is not a blocker) and continue with the roadmap. It only means ~1.5GB less GTT headroom, which is negligible on a 124GB system.

**Step 1.2: Disable IOMMU**
- Find IOMMU setting in BIOS
- Set to **Disabled** (provides ~6% memory read improvement)
- Only enable if you need VFIO/GPU passthrough later

**Step 1.3: Set Power Mode**
- Configure to **85W** (optimal balance: +19% vs 55W, avoids diminishing returns of 120W)

## Phase 2: Ubuntu 24.04 Base Installation

**Step 2.1: Install Ubuntu 24.04**
- Use Ubuntu 24.04 LTS Desktop or Server
- During installation, use default partitioning or your preferred scheme
- Complete initial setup (user account, timezone, etc.)

**Step 2.2: Initial System Update**
```bash
sudo apt update && sudo apt upgrade -y
```

## Phase 3: Critical Kernel Configuration

**Step 3.1: Install Mainline Kernel Tool**
```bash
sudo add-apt-repository ppa:cappelikan/ppa -y
sudo apt update
sudo apt install mainline -y
```

**Step 3.2: Install Kernel 6.16.9 or Later**
```bash
# Check available kernels
sudo mainline --list | grep "6.1[6-9]\|6.2"

# Install latest stable (e.g., 6.16.9 or 6.17.x)
sudo mainline --install 6.16.9

# Or manually download if needed
# sudo mainline --install-latest
```

**Step 3.3: Install Latest Firmware**
```bash
sudo apt install linux-firmware -y
# For bleeding edge (optional):
# sudo add-apt-repository ppa:firmware-testing/ppa -y
# sudo apt update && sudo apt install linux-firmware -y
```

**Step 3.4: Configure GRUB Boot Parameters**

Edit `/etc/default/grub`:
```bash
sudo nano /etc/default/grub
```

Modify the `GRUB_CMDLINE_LINUX_DEFAULT` line to include:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_iommu=off amdgpu.gttsize=131072 ttm.pages_limit=31457280"
```

Update GRUB and regenerate initramfs:
```bash
sudo update-grub
sudo update-initramfs -u -k all
```

**Step 3.5: Create AMD GPU Modprobe Configuration**

Create `/etc/modprobe.d/amdgpu_llm_optimized.conf`:
```bash
sudo nano /etc/modprobe.d/amdgpu_llm_optimized.conf
```

Add the following content:
```bash
# Legacy compatibility setting
options amdgpu gttsize=122800

# Primary GTT configuration - 120 GiB allocation
options ttm pages_limit=31457280

# Pre-allocate memory pool to reduce fragmentation
# This memory becomes permanently unavailable to the system
# Set equal to pages_limit for maximum performance
options ttm page_pool_size=31457280

# Optional: Increase fragment size for larger allocations
# Uncomment if experiencing fragmentation issues
# options amdgpu vm_fragment_size=8
```

Update initramfs:
```bash
sudo update-initramfs -u -k all
```

**Step 3.6: Reboot to New Kernel**
```bash
sudo reboot
```

After reboot, verify kernel:
```bash
uname -r  # Should show 6.16.9 or later
```

## Phase 4: GPU Access Configuration (Critical for Ubuntu)

**Step 4.1: Create udev Rules for GPU Access**

Create `/etc/udev/rules.d/99-amd-kfd.rules`:
```bash
sudo bash -c 'cat > /etc/udev/rules.d/99-amd-kfd.rules << EOF
SUBSYSTEM=="kfd", GROUP="render", MODE="0666", OPTIONS+="last_rule"
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", GROUP="render", MODE="0666", OPTIONS+="last_rule"
SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", GROUP="render", MODE="0666", OPTIONS+="last_rule"
EOF'
```

**IMPORTANT:** The `renderD[0-9]*` rule is critical for ROCm access. Without it, you'll get `HSA_STATUS_ERROR_OUT_OF_RESOURCES` errors when running `rocminfo`.

Reload udev rules:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Verify permissions:
```bash
ls -la /dev/kfd /dev/dri/
# All devices should show MODE 0666 (crw-rw-rw-)
```

**Step 4.2: Add User to GPU Groups**
```bash
sudo usermod -aG video,render $USER
```

## Phase 5: System Performance Optimization

**Step 5.1: Install and Configure tuned Daemon**
```bash
sudo apt install tuned -y
sudo systemctl enable --now tuned
sudo tuned-adm profile accelerator-performance
```

Verify activation:
```bash
tuned-adm active  # Should show "accelerator-performance"
```

This provides **+5-8% prompt processing performance improvement**.

## Phase 6: Container Environment Setup

**Step 6.1: Install Podman and Distrobox**

```bash
# Install Podman
sudo apt install podman -y

# Install Distrobox (toolbox is not available in Ubuntu repos)
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh
```

**NOTE:** Ubuntu 24.04 does not include `toolbox` in its repositories. We use **Distrobox** instead, which is fully compatible with Podman and provides the same functionality. All `toolbox` commands should be replaced with `distrobox` commands.

**Step 6.2: Configure Podman for GPU Access**

Ensure your user can run containers:
```bash
sudo loginctl enable-linger $USER
```

Verify installations:
```bash
podman --version      # Should show 4.9.3 or later
distrobox --version   # Should show 1.8.2.0 or later
```

## Phase 7: ROCm 7 RC with rocWMMA Setup

**Step 7.1: Create ROCm 7 RC Container with rocWMMA**

```bash
distrobox create llama-rocm-7rc-rocwmma \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render --group-add wheel --security-opt seccomp=unconfined"
```

**NOTE:** The command syntax differs from `toolbox`:
- Use `--additional-flags` instead of `--` separator
- Container creation may take a few minutes on first run

**Step 7.2: Enter the Container**
```bash
distrobox enter llama-rocm-7rc-rocwmma
```

Verify you're inside the container - you should see ROCm tools available:
```bash
rocm-smi          # Should show your GPU
rocminfo | head   # Should display HSA system info
```

## Phase 8: Verification and Testing

**Step 8.1: Verify GPU Memory Visibility**

On host system:
```bash
# Check all memory info
for file in /sys/class/drm/card*/device/mem_info*; do
  echo "$file: $(cat $file)";
done
```

**Expected values for Strix Halo APU:**
- `mem_info_vram_total`: 1073741824 bytes (1 GB - display framebuffer)
- `mem_info_gtt_total`: 137438953472 bytes (128 GB - unified compute memory)

**IMPORTANT:** For APUs with unified memory, the **GTT** (Graphics Translation Table) is what matters for LLM inference, not VRAM. This is normal and correct.

Inside ROCm container:
```bash
# Check ROCm visibility
rocminfo | grep -A100 'Agent 2' | grep -A50 'Pool Info'

# Expected: Should show ~120GB in Pool 1 and Pool 2
```

If you get `HSA_STATUS_ERROR_OUT_OF_RESOURCES`, verify:
```bash
# Check device permissions (should be 0666)
ls -la /dev/kfd /dev/dri/renderD128
# Fix if needed - see Step 4.1 udev rules
```

**Step 8.2: Test ROCm Functionality**
```bash
# Inside container
rocm-smi

# Should detect your gfx1151 GPU
```

**Step 8.3: Verify hipBLASlt Environment**
```bash
# Inside container
echo $ROCBLAS_USE_HIPBLASLT  # Should be "1"
```

## Phase 9: Build llama.cpp with rocWMMA

**Step 9.0: Install Build Dependencies**

The ROCm container is based on Fedora and doesn't include build tools by default. Install them first:

```bash
# Inside the container
sudo dnf install -y cmake gcc-c++ git libcurl-devel python3-pip
```

This will install:
- `cmake` - Build system generator
- `gcc-c++` - C++ compiler
- `git` - Version control (for cloning llama.cpp)
- `libcurl-devel` - CURL library (required by llama.cpp)

**Step 9.1: Clone and Build llama.cpp**

Inside the ROCm container:
```bash
cd ~
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# Build with rocWMMA support
cmake -B build -S . \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS="gfx1151" \
  -DGGML_HIP_ROCWMMA_FATTN=ON

cmake --build build --config Release -j$(nproc)
```

**NOTE:** The build process will take several minutes. You'll see compilation progress for GPU kernels and CPU code.

**NOTE on reproducibility:** llama.cpp is a fast-moving upstream project and HIP/rocWMMA support for gfx1151 has occasionally regressed between commits. This roadmap has been validated against commit `1f5accb8d` ("Fix garbled output with REPACK at high thread counts (#16956)", see `INITIAL_BENCHMARK.md`). If `git clone` (which tracks the latest commit on `master`) gives you build or runtime errors, try checking out that commit as a known-good baseline:
```bash
git checkout 1f5accb8d
```
Then re-run the `cmake -B build -S ...` and `cmake --build ...` commands above.

**If the build fails partway through with "corrupted file" or similar object-file errors** (commonly reported around 30-40% progress): this is almost always the OOM killer terminating a compiler process mid-write, not actual corruption. HIP/rocWMMA compilation units are memory-hungry, and `-j$(nproc)` (32 threads on this CPU) can exceed available RAM when many run concurrently. Reduce parallelism and retry, e.g.:
```bash
cmake --build build --config Release -j8
```
Lower the number further (e.g. `-j4`) if it still fails, and check `dmesg | grep -i "killed process"` to confirm an OOM kill occurred.

**Step 9.2: Install Build**
```bash
# Binaries will be in build/bin/
ls -lh build/bin/
```

## Phase 10: Download Models and Test

**Step 10.1: Set Up Model Directory**
```bash
# Outside container (in home directory to persist across container updates)
mkdir -p ~/models
cd ~/models
```

**Step 10.2: Download a Test Model**
```bash
# Inside container
# Install HuggingFace CLI if not already available
pip install "huggingface-hub[cli]" hf-transfer

# Enable fast downloads
export HF_HUB_ENABLE_HF_TRANSFER=1

# Download a model (example: Llama 2 7B)
hf download TheBloke/Llama-2-7B-GGUF llama-2-7b.Q4_K_M.gguf --local-dir ~/models
```
```

**Step 10.3: Run Inference Test**
```bash
cd ~/llama.cpp

# CRITICAL: Always use --no-mmap with GPU backends on Strix Halo
./build/bin/llama-cli \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --no-mmap \
  -ngl 99 \
  -p "Tell me about AMD Strix Halo processors" \
  -n 128
```

## Phase 11: Performance Validation

**Step 11.1: Run Benchmark**
```bash
cd ~/llama.cpp

# Benchmark prompt processing at 512 tokens
./build/bin/llama-bench \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  -mmp 0 \
  -ngl 99 \
  -p 512 \
  -n 128
```

**NOTE:** `llama-bench` uses `-mmp 0` (or `--mmap 0`) to disable mmap, not `--no-mmap` like `llama-cli`.

**Step 11.2: Monitor GPU Utilization**
```bash
# In another terminal, inside container
watch -n 1 rocm-smi
```

## Additional Recommendations

### For Multiple Backend Testing

**Create Vulkan Containers (Optional)**
```bash
# RADV (most stable)
distrobox create llama-vulkan-radv \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render"

# AMDVLK (fastest prompt processing)
distrobox create llama-vulkan-amdvlk \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-amdvlk \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render"
```

### Useful Tools

**Install VRAM Estimator**
```bash
# Clone helper scripts
git clone https://github.com/kyuz0/amd-strix-halo-toolboxes.git ~/strix-tools
```

**Refresh Containers Script**
```bash
cd ~/strix-tools
./refresh-toolboxes.sh llama-rocm-7rc-rocwmma
```

## Critical Reminders

1. **Always use `--no-mmap`** flag with llama.cpp on GPU backends
2. **Always use `--ngl 99`** (or 999) to offload all layers to GPU
3. **Store models in ~/models** (outside containers) to persist across updates
4. **Never use Ollama** - it lacks proper Vulkan/AMD support
5. **Kernel 6.16.9+** is critical for >15GB VRAM access
6. **Don't change VRAM allocation at OS level** after BIOS setup
7. **Set `ROCBLAS_USE_HIPBLASLT=1`** environment variable (already set in kyuz0 containers)

## Performance Expectations

- **Llama-2-7B**: ~50-52 tokens/second (similar to Apple M4 Max)
- **Prompt processing with rocWMMA**: 2× faster than Vulkan at BF16
- **Long context (8K+ tokens)**: ROCm rocWMMA excels (51 t/s vs Vulkan's 32 t/s)
- **Memory bandwidth**: ~212 GB/s internal, ~84 GB/s CPU-to-GPU

## Troubleshooting Quick Reference

### Ubuntu-Specific Issues

- **`toolbox` package not found**: Ubuntu 24.04 doesn't include `toolbox` in repos. Use `distrobox` instead (see Phase 6)
- **`HSA_STATUS_ERROR_OUT_OF_RESOURCES` when running `rocminfo`**: Missing renderD udev rule. Ensure `/etc/udev/rules.d/99-amd-kfd.rules` includes the `renderD[0-9]*` rule (see Step 4.1), then reload with `sudo udevadm control --reload-rules && sudo udevadm trigger`
- **Container can't access GPU**: Verify device permissions with `ls -la /dev/kfd /dev/dri/`. All should be `0666` (crw-rw-rw-)

### Build Issues in Container

- **`cmake: command not found`**: The ROCm container doesn't include build tools. Install them with `sudo dnf install -y cmake gcc-c++ git libcurl-devel` (see Step 9.0)
- **`Could NOT find CURL` error during cmake**: Install libcurl-devel with `sudo dnf install -y libcurl-devel`
- **Container uses `dnf` not `apt`**: The ROCm container is Fedora-based. Use `dnf` for package management, not `apt`
- **Build fails partway (e.g. ~30-40%) with "corrupted file" errors**: Usually an OOM kill during parallel compilation, not real corruption. Retry with lower parallelism, e.g. `cmake --build build --config Release -j8`, and confirm with `dmesg | grep -i "killed process"`. If errors persist, try the known-good commit `1f5accb8d` (see Step 9.1) since upstream HIP/rocWMMA support for gfx1151 has regressed between commits before

### llama.cpp Runtime Issues

- **`error: invalid argument: --ngl`**: Use `-ngl` (single dash) not `--ngl` (double dash) for GPU layer offloading
- **`error: invalid parameter for argument: --no-mmap`** (llama-bench): Use `-mmp 0` or `--mmap 0` instead. The `--no-mmap` flag only works with `llama-cli`, not `llama-bench`
- **`hf: command not found`**: The HuggingFace CLI changed to `hf download` instead of `huggingface-cli download`. If using pyenv, use full path: `~/.pyenv/versions/3.14.0/bin/hf`
- **Square brackets error in zsh** (`huggingface-hub[cli]`): Quote the package name: `pip install "huggingface-hub[cli]"`

### General Issues

- **Permission denied on GPU**: Check udev rules in Phase 4 and verify user is in `video` and `render` groups
- **Only 15.5GB VRAM visible**: Upgrade kernel to 6.16.9+
- **Slow model loading**: Add `--no-mmap` flag
- **ROCm crashes**: Try Vulkan RADV backend instead
- **Poor performance**: Verify `tuned-adm active` shows accelerator-performance
- **Confused about VRAM vs GTT**: For APUs, GTT (128GB) is what matters for compute, not VRAM (1GB). This is normal and expected.

## Next Steps After Setup

Once you have completed this roadmap and verified that everything works:

1. **Benchmark multiple backends** (ROCm 7 RC rocWMMA, Vulkan RADV, Vulkan AMDVLK) with your specific workloads
2. **Test with different model sizes** to find optimal configurations for your 120GB VRAM
3. **Explore long-context scenarios** where ROCm rocWMMA significantly outperforms Vulkan
4. **Monitor kernel updates** as gfx1151 support continues to mature
5. **Consider TheRock nightly builds** for bleeding-edge performance improvements

This roadmap gives you a production-ready setup for ROCm 7 RC with rocWMMA and hipBLASlt on your GMKTEC EVO-X2. The container-based approach ensures reproducibility and easy updates as ROCm support for gfx1151 continues maturing.
