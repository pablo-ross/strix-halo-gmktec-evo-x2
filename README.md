# Ubuntu 24.04 Setup for AMD Strix Halo (GMKTEC EVO-X2)

Configuration and documentation for optimizing Ubuntu 24.04 on AMD Ryzen AI Max+ 395 with Radeon 8060S for LLM inference using llama.cpp with ROCm 7 RC and rocWMMA.

## Hardware

- **System:** GMKTEC EVO-X2
- **CPU:** AMD RYZEN AI MAX+ 395 (32 threads)
- **GPU:** AMD Radeon Graphics gfx1151 (RDNA 3.5, 40 CUs)
- **Memory:** 124 GB RAM + 128 GB unified GPU memory (GTT)

## Documentation

### [ROADMAP.md](ROADMAP.md)
Complete step-by-step setup guide from BIOS configuration through llama.cpp installation and testing. Start here for initial system setup.

### [INITIAL_BENCHMARK.md](INITIAL_BENCHMARK.md)
Performance benchmark results for Llama-2-7B Q4_K_M model showing:
- Prompt processing: 871.77 t/s (512 tokens)
- Text generation: 43.83 t/s
- Memory usage and system configuration details

### [LLAMA.CPP_SERVER.md](LLAMA.CPP_SERVER.md)
Guide for running llama.cpp as a network-accessible server with:
- Local network setup
- OpenAI-compatible API configuration
- Systemd service configuration
- Security and performance tuning
- Multi-model deployment

### [CLAUDE.md](CLAUDE.md)
Quick reference guide for Claude Code with common commands, troubleshooting steps, and critical configuration details.

## Quick Start

```bash
# Enter the ROCm container
distrobox enter llama-rocm-7rc-rocwmma

# Run inference
cd ~/llama.cpp
./build/bin/llama-cli \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --no-mmap \
  -ngl 99 \
  -p "Your prompt here"

# Start server
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap
```

## Key Features

- ✅ 120GB unified memory for large models (70B+)
- ✅ ROCm 7 RC with rocWMMA and hipBLASlt
- ✅ Container-based environment (Distrobox)
- ✅ OpenAI-compatible API server
- ✅ Optimized for long-context inference (32K+ tokens)

## Important Notes

- **Always use `--no-mmap`** flag with GPU backends
- **Always use `-ngl 99`** to offload all layers to GPU
- **Kernel 6.16.9+** required for full memory access
- **GTT memory** (128GB) is used for compute, not VRAM (1GB)

## References

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [AMD Strix Halo Toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)
- [ROCm Documentation](https://rocm.docs.amd.com/)
