# GPU & LLM Setup Optimization Plan

**System:** AMD Ryzen AI Max+ 395 with Radeon 8060S (Strix Halo)
**Analysis Date:** 2025-11-09
**Reference:** https://github.com/kyuz0/amd-strix-halo-toolboxes

---

## Executive Summary

Current 4-model setup is **functional and well-designed**, but running on pre-release software with untapped optimization potential. Key finding: Switch to stable container and consider Vulkan backend for performance gains.

**Current Status:**
- ✅ 4 models running successfully
- ✅ 60% memory utilization (77.5 GB / 128 GB)
- ✅ All health checks passing
- ⚠️ Using pre-release ROCm 7 RC (unstable)
- ⚠️ Missing 8 GB memory due to suboptimal kernel params
- ⚠️ Backend choice not benchmarked for workload

---

## Current Configuration Analysis

### Hardware & Kernel
```
Kernel: 6.16.9-061609-generic ✅
GPU: AMD Radeon Graphics (gfx1151) ✅
GTT Memory: 128 GB total / 77.5 GB used (60%)
Boot Params: amd_iommu=off amdgpu.gttsize=131072 ttm.pages_limit=31457280
```

### Container Setup
```
Container: llama-rocm-7rc-rocwmma
Status: Pre-release/unstable ⚠️
ROCm Version: 7.1.25403 (Release Candidate)
Backend: HIP/ROCm only (Vulkan disabled)
```

### Build Configuration
```
GGML_HIP: ON
GGML_HIP_ROCWMMA_FATTN: ON ✅
GGML_HIP_MMQ_MFMA: ON ✅
GGML_VULKAN: OFF
AMDGPU_TARGETS: gfx1151 ✅
```

### Running Models

| Model | Port | Context | Memory (est) | Quantization | Status |
|-------|------|---------|--------------|--------------|--------|
| Qwen3-Coder-30B | 8080 | 256K | ~35-40 GB | Q8_K_XL | ✅ Running |
| Bielik-11B | 8081 | 64K | ~15 GB | Q4_K_M | ✅ Running |
| Qwen2.5-7B | 8082 | 16K | ~8 GB | Q5_K_M | ✅ Running |
| Nomic Embed v2 MoE | 8083 | 8K | ~3 GB | F16 | ✅ Running |
| **Total** | | | **~66 GB** | | |

**Available headroom:** ~50 GB for additional models or larger contexts

---

## Optimization Opportunities

### Priority 1: Container Stability (High Impact)

**Issue:** Currently using `rocm-7rc-rocwmma` (pre-release)
**Recommended:** `rocm-6.4.4-rocwmma` (stable, officially recommended by kyuz0)
**Impact:** Better stability for production workloads
**Risk:** RC versions may have bugs or breaking changes

**Action:**
```bash
# Backup current container state if needed
distrobox list

# Remove RC container
distrobox rm llama-rocm-7rc-rocwmma

# Create stable container
distrobox create llama-rocm-6.4.4-rocwmma \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-6.4.4-rocwmma \
  --additional-flags "--device /dev/dri --device /dev/kfd \
    --group-add video --group-add render --group-add sudo \
    --security-opt seccomp=unconfined"

# Rebuild llama.cpp inside container
distrobox enter llama-rocm-6.4.4-rocwmma
cd ~/llama.cpp
cmake -B build -S . \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS="gfx1151" \
  -DGGML_HIP_ROCWMMA_FATTN=ON \
  -DGGML_HIP_MMQ_MFMA=ON
cmake --build build --config Release -j$(nproc)
```

**Effort:** Medium (30-60 minutes including rebuild)
**Downtime:** Required (stop all services during migration)

---

### Priority 2: Backend Performance Testing (Medium-High Impact)

**Issue:** Current build uses HIP/ROCm only; Vulkan RADV may be faster
**Benchmark Data (kyuz0):**
- Vulkan RADV: 10 first-place finishes in token generation (tg128)
- ROCm 6.4.4: Better for prompt processing
- Performance varies by model architecture and quantization

**Recommendation:** Test both backends with actual workload

**Option A: Create Test Container**
```bash
# Create Vulkan RADV container (parallel to ROCm)
distrobox create llama-vulkan-radv-test \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv \
  --additional-flags "--device /dev/dri --group-add video --group-add render \
    --security-opt seccomp=unconfined"

# Build llama.cpp for Vulkan
distrobox enter llama-vulkan-radv-test
cd ~/llama.cpp
cmake -B build -S . -DGGML_VULKAN=ON
cmake --build build --config Release -j$(nproc)
```

**Option B: Hybrid Architecture (Advanced)**
Run workload-specific backends:
- ROCm: Qwen3-Coder-30B (large context, reasoning)
- Vulkan RADV: Qwen2.5-7B, Bielik-11B (high-throughput inference)
- Either: Nomic Embed (embeddings workload)

**Benchmarking:**
```bash
# Inside container, test with your actual model
./build/bin/llama-bench \
  -m /models/qwen2.5-coder-7b-instruct-q5_k_m.gguf \
  -mmp 0 \
  -ngl 99 \
  -p 512 \
  -n 128 \
  -r 3
```

**Effort:** Medium (2-4 hours for testing)
**Downtime:** None (can run parallel to production)

---

### Priority 3: Kernel Memory Limit (Low Impact, Easy Fix)

**Issue:** Current TTM pages limit wastes 8 GB
**Current:** `ttm.pages_limit=31457280` (120 GB)
**Recommended:** `ttm.pages_limit=33554432` (128 GB)
**Impact:** +8 GB for larger contexts or additional models

**Action:**
```bash
# Edit GRUB configuration
sudo nano /etc/default/grub

# Update line to:
GRUB_CMDLINE_LINUX="amd_iommu=off amdgpu.gttsize=131072 ttm.pages_limit=33554432"

# Apply changes
sudo update-grub
sudo reboot
```

**Effort:** Low (5 minutes + reboot)
**Downtime:** Required (reboot)

---

### Priority 4: Configuration Tuning (Low Impact, Optional)

#### Qwen3-Coder Context Reduction
**Current:** `-c 262144` (256K context)
**Consideration:** If not using full context, reduce to save ~20 GB:
```bash
-c 131072  # 128K context (still very large)
-c 65536   # 64K context (typical for IDE usage)
```

**File:** `/home/username/wrappers/qwen3-coder-server.sh:33`

#### Flash Attention Verification
Confirm all services use flash attention where available:
```bash
-fa  # or --flash-attn
```

Currently using `--cache-type-k f16` which is compatible with ROCWMMA flash attention.

#### Batch Size Optimization
Current batch sizes are reasonable:
- Qwen3-Coder: `-b 2048` (good for frequent small requests)
- Bielik-11B: `-b 4096` (good for larger prompts)
- Qwen2.5-7B: `-b 512` (optimized for autocomplete)
- Nomic Embed: `-b 2048` (good for batch embeddings)

**Action:** Monitor actual request patterns and adjust if needed.

---

## Missing Tools & Resources

### VRAM Estimator
kyuz0 repository mentions `gguf-vram-estimator.py` for memory planning.

**Status:** Not found in current container
**Action:** Download from repository (if available) or estimate manually:

**Manual Estimation Formula:**
```
Memory = Model Size + (Context * 2 bytes * Hidden Dim * Layers / 1024^3)

Example (Qwen3-Coder-30B Q8_K):
- Model: ~31 GB
- Context (256K): ~31 GB @ full context
- Total: ~62 GB (matches observations)
```

---

## Multi-Model Architecture Assessment

### Current Design: ✅ Excellent

**Strengths:**
1. Workload specialization (autocomplete vs. chat vs. embeddings)
2. Isolated ports prevent conflicts
3. Parallel processing (4-16 slots per model)
4. Memory headroom for traffic spikes
5. Proper systemd service management

**Capacity Analysis:**
- Current: 4 models @ ~66 GB (60% utilization)
- Potential: 5-6 models possible with optimization
- Constraint: CPU threads (32 total, ~16-20 per model = bottleneck at 6+ models)

### Potential 5th Model
With current memory (~50 GB free), options include:
- DeepSeek-R1 distill 7B-14B (reasoning specialist)
- CodeLlama 34B Q4 (code-focused alternative)
- Mistral Large Q4 (general-purpose backup)

**Port assignment:** 8084 (deepseek-r1-server.service already exists)

---

## Backend Performance Comparison

### Source: kyuz0/amd-strix-halo-toolboxes

#### Token Generation (tg128)
| Backend | First Place | Characteristics |
|---------|-------------|-----------------|
| Vulkan RADV | 10 wins | **Best for high-throughput inference** |
| Vulkan AMDVLK | 3 wins | Fastest but 2 GiB buffer limit |
| ROCm 6.4.4 + ROCWMMA | Mixed | Balanced, hipBLASLt optimized |
| ROCm 7 RC | Mixed | Pre-release, experimental |

#### Prompt Processing (pp512)
| Backend | First Place | Characteristics |
|---------|-------------|-----------------|
| ROCm 6.4.4 | 6 wins | **Best for large prompts** |
| Vulkan AMDVLK | 6 wins | Fast but memory constrained |
| Vulkan RADV | Fewer | Stable across models |

#### Recommendation by Workload
- **Continue.dev autocomplete:** Vulkan RADV (fast token gen)
- **Large context reasoning:** ROCm 6.4.4 (prompt processing)
- **Embeddings:** Either (workload-dependent)
- **Balanced production:** ROCm 6.4.4 + ROCWMMA (current choice)

---

## Recommended Migration Path

### Phase 1: Stabilization (High Priority)
**Timeline:** 1-2 hours
**Downtime:** Required

1. ✅ Stop all llama services
2. ✅ Backup current wrapper scripts (already in repo)
3. ✅ Create stable `rocm-6.4.4-rocwmma` container
4. ✅ Rebuild llama.cpp with same flags
5. ✅ Update wrapper scripts (change container name)
6. ✅ Test each service individually
7. ✅ Enable all services

**Commands:**
```bash
# Stop services
sudo systemctl stop llama-server bielik-server qwen25-7b-server nomic-embed-server

# Container migration (see Priority 1)

# Update wrapper scripts
cd ~/wrappers
sed -i 's/llama-rocm-7rc-rocwmma/llama-rocm-6.4.4-rocwmma/g' *.sh

# Test individual service
sudo systemctl start llama-server
curl http://localhost:8080/health

# Enable all when confirmed working
sudo systemctl start bielik-server qwen25-7b-server nomic-embed-server
```

### Phase 2: Performance Optimization (Medium Priority)
**Timeline:** 4-8 hours
**Downtime:** None (parallel testing)

1. ✅ Create Vulkan RADV test container
2. ✅ Rebuild llama.cpp for Vulkan
3. ✅ Run benchmarks on test port (8090)
4. ✅ Compare with ROCm performance
5. ✅ Document findings
6. ⚠️ Migrate if >15% improvement (optional)

### Phase 3: Kernel Optimization (Low Priority)
**Timeline:** 15 minutes + reboot
**Downtime:** Required

1. ✅ Update kernel params
2. ✅ Reboot
3. ✅ Verify GTT memory increased
4. ✅ Monitor for 24 hours

### Phase 4: Fine-Tuning (Optional)
**Timeline:** Ongoing
**Downtime:** None

1. ⚠️ Monitor actual request patterns
2. ⚠️ Adjust batch sizes based on metrics
3. ⚠️ Optimize context windows
4. ⚠️ Consider 5th model deployment

---

## Monitoring & Validation

### Pre-Migration Baseline
```bash
# Capture current performance
./benchmark_server.sh  # Your existing script

# Memory usage
for file in /sys/class/drm/card*/device/mem_info*; do
  echo "$file: $(cat $file)";
done

# Service metrics
sudo systemctl status llama-server --no-pager | grep Memory
```

### Post-Migration Validation
```bash
# Verify all services healthy
curl http://localhost:8080/health
curl http://localhost:8081/health
curl http://localhost:8082/health
curl http://localhost:8083/health

# Check ROCm detection
distrobox enter llama-rocm-6.4.4-rocwmma -- rocminfo | grep -A50 'Agent 2'

# Re-run benchmarks
./benchmark_server.sh

# Compare results
```

### Success Criteria
- ✅ All services return `{"status":"ok"}`
- ✅ Performance within ±5% of baseline (or better)
- ✅ No service crashes for 24 hours
- ✅ Memory usage stable
- ✅ Logs show no errors

---

## Risk Assessment

### Container Migration (Priority 1)
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Build fails | Low | High | Keep RC container until validated |
| Performance regression | Low | Medium | Benchmark before/after |
| Config incompatibility | Low | Low | Scripts already compatible |

### Backend Change (Priority 2)
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Slower performance | Medium | Medium | Benchmark first, don't migrate if slower |
| Model incompatibility | Low | Medium | Test all 4 models before production |
| Driver issues | Low | High | Can revert to ROCm easily |

### Kernel Changes (Priority 3)
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Boot failure | Very Low | High | GRUB has fallback boot options |
| Memory allocation issues | Very Low | Medium | Can revert parameter easily |

---

## Open Questions

1. **Benchmark Data Gap:** kyuz0 repo doesn't publish absolute tokens/second numbers - only rankings. Need to benchmark our specific models.

2. **Flash Attention Vulkan:** Does Vulkan backend support flash attention equivalent to ROCWMMA? (Likely through Vulkan shaders)

3. **Hybrid Container Management:** Is there overhead running two distrobox containers simultaneously? (Minimal - both share host resources)

4. **Future ROCm 7 Stable:** When ROCm 7 stable releases, will it outperform 6.4.4? (Unknown - monitor kyuz0 repo for updates)

---

## Resources & References

- kyuz0 Toolboxes: https://github.com/kyuz0/amd-strix-halo-toolboxes
- Docker Hub Images: https://hub.docker.com/r/kyuz0/amd-strix-halo-toolboxes/tags
- llama.cpp: https://github.com/ggerganov/llama.cpp
- ROCm Documentation: https://rocm.docs.amd.com/

---

## Conclusion

Your 4-model setup demonstrates excellent architecture and configuration practices. The primary concern is software stability (pre-release ROCm 7 RC). Recommended immediate action:

**Phase 1 (High Priority):** Migrate to stable `rocm-6.4.4-rocwmma` container
**Phase 2 (Explore):** Benchmark Vulkan RADV for potential performance gains
**Phase 3 (Optional):** Increase kernel memory limit (+8 GB)

**Current Grade:** A- (excellent design, suboptimal backend choice)
**Post-Optimization Grade:** A+ (production-ready, stable, performant)
