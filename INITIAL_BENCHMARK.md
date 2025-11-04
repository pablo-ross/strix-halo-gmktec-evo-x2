# Initial Performance Benchmark - AMD Strix Halo (GMKTEC EVO-X2)

**Date:** November 4, 2025
**Setup:** Ubuntu 24.04 LTS + ROCm 7 RC + llama.cpp with rocWMMA
**Test Model:** Llama-2-7B Q4_K_M (3.80 GiB)

---

## System Configuration

### Hardware

**CPU:** AMD RYZEN AI MAX+ 395 w/ Radeon 8060S
- 32 threads available
- System RAM: 124 GiB

**GPU:** AMD Radeon Graphics (gfx1151)
- **Architecture:** RDNA 3.5 (Strix Halo)
- **Chip ID:** 0x1586
- **Compute Units:** 40 CUs
- **SIMDs per CU:** 2
- **Shader Engines:** 2
- **Max Clock:** 2900 MHz
- **Wavefront Size:** 32
- **Fast F16:** TRUE
- **Cache:**
  - L1: 32 KB
  - L2: 2048 KB (2 MB)
  - L3: 32768 KB (32 MB)

### Memory Configuration

**VRAM (Framebuffer):**
- Total: 1,073,741,824 bytes (1 GB)
- Used: 163,119,104 bytes (~156 MB)

**GTT (Graphics Translation Table - Unified Memory):**
- Total: 137,438,953,472 bytes (128 GB)
- Used: 18,620,416 bytes (~18 MB)
- **Note:** For APUs, GTT is the primary compute memory pool

### Software Stack

**Operating System:**
- Distribution: Ubuntu 24.04.3 LTS (Noble)
- Kernel: 6.16.9-061609-generic

**ROCm:**
- Version: ROCm 7.0 RC
- HIP Version: 7.1.25403-6f01e3f968
- Clang: 20.0.0git
- VBIOS: 113-STRXLGEN-001

**llama.cpp:**
- Build: 1f5accb8d (commit hash)
- Commit: "Fix garbled output with REPACK at high thread counts (#16956)"
- Backend: ROCm (HIP)
- Configured with:
  - `GGML_HIP=ON`
  - `AMDGPU_TARGETS=gfx1151`
  - `GGML_HIP_ROCWMMA_FATTN=ON`
  - `GGML_HIP_MMQ_MFMA=ON`

**Container:**
- Tool: Distrobox 1.8.2.0
- Base Image: docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7rc-rocwmma
- Container OS: Fedora 44 (Rawhide)

---

## Benchmark Results

### Test Configuration

**Model:** Llama-2-7B Q4_K_M
- Model Size: 3.80 GiB
- Parameters: 6.74 B
- Quantization: Q4_K_M (4-bit with K-quant)
- GPU Layers Offloaded: 99 (all layers)
- Memory Mapping: Disabled (-mmp 0)

**Test Parameters:**
- Repetitions: 3 runs per test
- Backend: ROCm (GPU only)
- Batch Size: 2048 (default)
- Context Size: 4096 (default)

### Performance Summary

| Test Type | Prompt Tokens | Generation Tokens | Performance (t/s) | Std Dev |
|-----------|--------------|-------------------|-------------------|---------|
| Prompt Processing | 128 | - | **526.75** | ±1.08 |
| Prompt Processing | 256 | - | **748.60** | ±1.37 |
| Prompt Processing | 512 | - | **871.77** | ±2.71 |
| Prompt Processing | 1024 | - | **778.30** | ±1.77 |
| Text Generation | - | 128 | **43.83** | ±0.07 |

### Detailed Benchmark Output

```
| model                          |       size |     params | backend    | ngl | mmap |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ---: | --------------: | -------------------: |
| llama 7B Q4_K - Medium         |   3.80 GiB |     6.74 B | ROCm       |  99 |    0 |           pp128 |        526.75 ± 1.08 |
| llama 7B Q4_K - Medium         |   3.80 GiB |     6.74 B | ROCm       |  99 |    0 |           pp256 |        748.60 ± 1.37 |
| llama 7B Q4_K - Medium         |   3.80 GiB |     6.74 B | ROCm       |  99 |    0 |           pp512 |        871.77 ± 2.71 |
| llama 7B Q4_K - Medium         |   3.80 GiB |     6.74 B | ROCm       |  99 |    0 |          pp1024 |        778.30 ± 1.77 |
| llama 7B Q4_K - Medium         |   3.80 GiB |     6.74 B | ROCm       |  99 |    0 |           tg128 |         43.83 ± 0.07 |
```

---

## Performance Analysis

### Strengths

✅ **Excellent Prompt Processing:**
- Peak performance at 512 tokens: **871.77 t/s**
- Scales well from 128-512 tokens
- Very low variance (±2.71 at worst), indicating stable performance
- rocWMMA acceleration is clearly effective for batch processing

✅ **Good Text Generation:**
- Consistent performance: **43.83 ± 0.07 t/s**
- Extremely low variance indicates stable GPU clocks
- Sufficient for interactive use cases

✅ **Memory Efficiency:**
- Only 3.82 GB GPU memory used for 7B model
- Plenty of headroom for larger models (up to ~120GB available)
- No memory pressure or swapping

### Performance Comparison

| Metric | This System | Expected (Roadmap) | vs Target |
|--------|-------------|-------------------|-----------|
| Prompt Processing (512) | 871.77 t/s | ~850 t/s | ✅ +2.6% |
| Text Generation | 43.83 t/s | 50-52 t/s | ⚠️ -13.5% |

### Observations

**Text Generation Performance:**
- Performing at ~87% of expected peak (43.83 vs 50-52 t/s)
- Possible factors:
  1. Power management (GPU in low-power state per rocm-smi warning)
  2. First-time run (kernel compilation caching)
  3. Thermal constraints
  4. Background processes
  5. BIOS settings (power mode verification needed)

**Prompt Processing Performance:**
- **Exceeds expectations** at optimal batch size (512 tokens)
- Shows optimal sweet spot at 512 tokens before slight drop at 1024
- rocWMMA is working effectively for batched operations

---

## GPU Memory Usage During Inference

From llama-cli run with 139 tokens:

```
| memory breakdown [MiB] |  total     free    self   model   context   compute    unaccounted |
|   - ROCm0 (Graphics)   | 122880 = 116600 + (5961 =  3820 +    2048 +      92) +         318 |
|   - Host               |                      86 =    70 +       0 +      16                |
```

**Analysis:**
- Total GPU memory pool: 122,880 MiB (120 GB)
- Model weight memory: 3,820 MiB (~3.73 GB)
- Context memory: 2,048 MiB (2 GB for 4K context)
- Compute buffers: 92 MiB
- Free memory: 116,600 MiB (113.9 GB available)
- Host memory: 86 MiB

**Capacity Estimation:**
- Can fit models up to ~110GB comfortably
- Support for 70B+ models with large quantizations
- Multiple 7B models simultaneously possible

---

## Kernel and Driver Configuration

### Active Kernel Parameters

From `/proc/cmdline`:
```
amd_iommu=off amdgpu.gttsize=131072 ttm.pages_limit=31457280
```

**Configuration:**
- IOMMU: Disabled (for performance)
- GTT Size: 131,072 MB (128 GB)
- TTM Pages Limit: 31,457,280 pages (120 GB @ 4KB pages)

### GPU Power State

**Note:** rocm-smi reports:
```
WARNING: AMD GPU device(s) is/are in a low-power state.
Check power control/runtime_status
```

This may indicate GPU power management is enabled, potentially limiting performance.

**Recommendation:** Verify BIOS power settings and consider setting to performance mode for optimal inference speed.

---

## Test Commands Used

### Benchmark Command
```bash
./build/bin/llama-bench \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  -mmp 0 \
  -ngl 99 \
  -p 128,256,512,1024 \
  -n 128 \
  -r 3
```

### Interactive Inference
```bash
./build/bin/llama-cli \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --no-mmap \
  -ngl 99 \
  -p "Tell me about AMD Strix Halo processors" \
  -n 128
```

---

## Known Issues and Workarounds

### 1. GPU Power State Warning
**Issue:** rocm-smi reports GPU in low-power state
**Impact:** May reduce performance by 10-15%
**Fix:** Check `/sys/class/drm/card1/device/power_dpm_force_performance_level` and set to `high` if needed

### 2. Optimal Batch Size
**Observation:** Best prompt processing at 512 tokens, drops slightly at 1024
**Recommendation:** Use batch sizes around 512 tokens for optimal throughput

---

## Next Steps

### Recommended Actions

1. **Power Management Tuning:**
   - Verify GPU is not throttling
   - Check BIOS power settings (should be 85W mode)
   - Consider disabling GPU power management for inference workloads

2. **Additional Testing:**
   - Test with larger models (13B, 30B, 70B)
   - Long-context testing (8K, 16K, 32K tokens)
   - Mixed precision benchmarks
   - Compare with Vulkan backend for reference

3. **Optimization:**
   - Profile memory bandwidth utilization
   - Test different batch sizes for specific workloads
   - Experiment with different quantization formats (Q5, Q6, Q8)

---

## Conclusion

The AMD Strix Halo system with ROCm 7 RC and rocWMMA demonstrates **excellent prompt processing capabilities** (871.77 t/s) and **good text generation performance** (43.83 t/s). While text generation is slightly below the expected 50-52 t/s target, the system is stable, has massive memory capacity for large models, and shows great potential for optimization.

The 120GB unified memory pool makes this platform particularly attractive for:
- Running large 70B+ models
- Long-context applications (32K+ tokens)
- Multi-model serving
- Fine-tuning and development work

**Overall Rating:** ⭐⭐⭐⭐ (4/5) - Excellent for LLM workloads with room for optimization
