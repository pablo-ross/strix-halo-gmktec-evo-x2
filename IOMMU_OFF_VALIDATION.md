# IOMMU-Off Validation Report

**Date:** 2026-07-23
**System:** GMKTEC EVO-X2 (AMD Ryzen AI Max+ 395, Radeon 8060S)
**Kernel:** 7.0.0-28-generic
**Config:** `amd_iommu=off` in GRUB_CMDLINE_LINUX_DEFAULT

## Validation Checks

| Check | Result | Evidence |
|-------|--------|----------|
| Kernel cmdline | ✅ `amd_iommu=off` present | `cat /proc/cmdline` |
| IOMMU groups in sysfs | ✅ Empty — no groups | `ls /sys/kernel/iommu_groups/` → 0 entries |
| AMD-Vi driver init in boot log | ✅ Zero references | `journalctl -k \| grep "AMD-Vi"` → no matches |
| GPU DMA | ✅ Direct — no IOMMU translation | GPU has no iommu_group |
| NPU amdxdna | ✅ Expected SVA failure (IOMMU required) | Confirms IOMMU is off |

## Live Inference Validation

**Backend:** Vulkan (Radeon 8060S)
**Model:** Qwen3-4B-Q4_K_M

### Prompt Processing

| Context Length | Tokens/s | Std Dev |
|---------------|----------|---------|
| 128 tok | 2,138 t/s | ±10 |
| 1,024 tok | 1,748 t/s | ±2 |
| 2,048 tok | 1,615 t/s | ±1 |
| 4,096 tok | 1,338 t/s | ±1 |

### Generation (from 512-token prompt)

| Gen Length | Tokens/s | Std Dev |
|-----------|----------|---------|
| 128 tok | 75.6 t/s | ±0.14 |
| 256 tok | 75.8 t/s | ±0.25 |

### Stability

- No GPU compute ring timeouts
- No DRM errors during inference
- No device resets
- Low sample variance (<1% for most cells)

## Reference

Based on the Frontier Lab field report:
https://thefrontierlab.ai/strix-halo-tuning-part-two-iommu/

Measured gains with IOMMU off vs on (from article):
- Dense prompt processing (empty): **+37.5%**
- Dense prompt processing (32k): **+34.1%**
- MoE prompt processing (empty): **+6.7%**
- Generation: **+0.6 to +1.4%** (within noise)
