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

### [LLAMA_ISSUES_SUMMARY.md](LLAMA_ISSUES_SUMMARY.md)
Incident writeup on a kernel 6.17 update breaking the KFD ABI against the ROCm 7.0-rc distrobox container, and the fix (moving to a native-host ROCm 7.2 build). Read this if llama-server crashes after a kernel update, or if you're deciding between the container and native-host build paths.

### [OPTIMIZATION_PLAN.md](OPTIMIZATION_PLAN.md), [MULTI_MODEL_DEPLOYMENT.md](MULTI_MODEL_DEPLOYMENT.md), [MULTI_MODEL_SUMMARY.md](MULTI_MODEL_SUMMARY.md), [MULTI_SERVER_STARTUP_ANALYSIS.md](MULTI_SERVER_STARTUP_ANALYSIS.md), [QWEN3-CODER-30B_BENCHMARK.md](QWEN3-CODER-30B_BENCHMARK.md)
Follow-on notes covering running multiple models concurrently and per-model benchmark/tuning results.

### [systemctl/](systemctl/) and [wrappers/](wrappers/)
Production systemd unit files and matching launch scripts, one pair per model currently served (Qwen3-Coder-30B, Bielik 11B/4.5B, DeepSeek-R1, GPT-OSS-20B, Qwen2.5-7B, E5-Large-v2, Nomic Embed). Each wrapper execs `llama-server` natively on the host on its own port; see CLAUDE.md for the full list.

### [nginx/](nginx/)
OpenAI-compatible API gateway that routes requests to the right per-model llama-server instance based on the `"model"` field.

### [docker-relay/](docker-relay/)
Dockerized relay (nginx + FastAPI + Cloudflare Tunnel) for exposing local models to external clients without opening inbound firewall ports.

## Quick Start

**Current setup runs llama.cpp natively on the host with ROCm 7.2** (see [LLAMA_ISSUES_SUMMARY.md](LLAMA_ISSUES_SUMMARY.md) for why — the original distrobox container's ROCm 7.0-rc runtime broke against kernel 6.17+). The distrobox path in ROADMAP.md still works for getting your first build running; switch to native once you hit that issue or want a production setup.

```bash
cd ~/llama.cpp
export LD_LIBRARY_PATH="/opt/rocm-7.2.0/lib"

# Run inference
./build/bin/llama-cli \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --no-mmap \
  -fa 1 \
  -ngl 99 \
  -p "Your prompt here"

# Start server
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  -fa 1 \
  --no-mmap
```

## Key Features

- ✅ 120GB unified memory for large models (70B+)
- ✅ ROCm 7.2 native host build (with a Distrobox-based path for initial setup)
- ✅ OpenAI-compatible API server, with nginx gateway for routing across multiple concurrently-running models
- ✅ Optimized for long-context inference (32K+ tokens)

## Important Notes

- **Always use `--no-mmap`** flag with GPU backends
- **Always use `-ngl 99`** to offload all layers to GPU
- **Always use `-fa 1`** (flash attention) on Strix Halo to avoid crashes
- **Kernel 6.16.9+** required for full memory access; kernel 6.17+ needs ROCm 7.2 native host build, not the older distrobox container (see LLAMA_ISSUES_SUMMARY.md)
- **GTT memory** (128GB) is used for compute, not VRAM (1GB)

## References

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [AMD Strix Halo Toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)
- [ROCm Documentation](https://rocm.docs.amd.com/)
