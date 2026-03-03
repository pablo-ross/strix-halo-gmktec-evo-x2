# LLM API Gateway - Nginx with Dynamic Model Routing

Unified OpenAI-compatible API endpoint that automatically routes requests to different LLM backends based on the model name in the request.

## Features

✅ **OpenAI API Compatible** - Drop-in replacement for OpenAI API
✅ **Dynamic Model Routing** - Routes based on `"model"` field in JSON
✅ **Single Endpoint** - One URL for all models
✅ **Easy to Extend** - Add new models via `.env` file
✅ **Streaming Support** - Full SSE streaming support
✅ **Pattern Matching** - Flexible model name matching

## Quick Start

### 1. Initial Setup

```bash
# Create .env from example
cp .env.example .env

# Edit .env to match your setup
nano .env

# Run setup (requires sudo for package installation)
sudo ./setup.sh
```

### 2. Test Configuration

```bash
./test.sh
```

### 3. Use the API

```bash
# Single endpoint for all models
curl http://10.0.0.60/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-Coder-30B-A3B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Configuration

### Model Definition Format

In `.env`, define models using:

```bash
MODEL_N=NAME:PORT:pattern1,pattern2,...
```

**Example:**
```bash
MODEL_1=QWEN3:8080:qwen,qwen3,coder
MODEL_2=BIELIK:8081:bielik
```

**Explanation:**
- `MODEL_1` - Sequential number (1, 2, 3, ...)
- `QWEN3` - Display name (used in logs)
- `8080` - Backend port where llama-server is running
- `qwen,qwen3,coder` - Comma-separated patterns for routing

### How Routing Works

The gateway inspects the `"model"` field in JSON requests:

1. **Exact match**: `"model": "Qwen3-Coder-30B-A3B-Instruct"` → Port 8080
2. **Pattern match**: `"model": "some-qwen-variant"` → Port 8080 (contains "qwen")
3. **Default**: No match or no model field → Default model (first in config)

### Adding a New Model

1. **Start your llama-server** on a new port (e.g., 8082):
   ```bash
   llama-server -m model.gguf --port 8082
   ```

2. **Edit `.env`** and add:
   ```bash
   MODEL_3=LLAMA3:8082:llama,llama3
   ```

3. **Re-run setup**:
   ```bash
   sudo ./setup.sh
   ```

4. **Test**:
   ```bash
   ./test.sh
   ```

That's it! The new model is now available at the same URL.

## Files

- **`.env`** - Configuration (model definitions, ports, etc.)
- **`setup.sh`** - Installation and configuration script
- **`test.sh`** - Test script to verify routing
- **`README.md`** - This file

## API Endpoints

### Chat Completions

```bash
POST /v1/chat/completions
Content-Type: application/json

{
  "model": "Qwen3-Coder-30B-A3B-Instruct",
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

### List Models

```bash
GET /v1/models
```

Returns models from the default backend.

### Health Check

```bash
GET /health
```

Returns `200 OK` if gateway is running.

## Client Configuration

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://10.0.0.60/v1",
    api_key="not-needed"
)

# Route to Qwen3 (port 8080)
response = client.chat.completions.create(
    model="Qwen3-Coder-30B-A3B-Instruct",
    messages=[{"role": "user", "content": "Hello"}]
)

# Route to Bielik (port 8081)
response = client.chat.completions.create(
    model="Bielik-11B-v3.0-Instruct",
    messages=[{"role": "user", "content": "Cześć"}]
)
```

### Continue.dev

```json
{
  "models": [
    {
      "title": "Qwen3 Coder 30B",
      "provider": "openai",
      "model": "Qwen3-Coder-30B-A3B-Instruct",
      "apiBase": "http://10.0.0.60/v1"
    },
    {
      "title": "Bielik 11B",
      "provider": "openai",
      "model": "Bielik-11B-v3.0-Instruct",
      "apiBase": "http://10.0.0.60/v1"
    }
  ]
}
```

### Curl

```bash
# Qwen3 (English coding model)
curl http://10.0.0.60/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-Coder-30B-A3B-Instruct",
    "messages": [{"role": "user", "content": "Write a Python function"}]
  }'

# Bielik (Polish language model)
curl http://10.0.0.60/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Bielik-11B-v3.0-Instruct",
    "messages": [{"role": "user", "content": "Napisz funkcję w Pythonie"}]
  }'
```

## Troubleshooting

### Check nginx status
```bash
sudo systemctl status nginx
```

### View nginx logs
```bash
sudo tail -f /var/log/nginx/error.log
```

### Test nginx config
```bash
sudo nginx -t
```

### Reload after manual changes
```bash
sudo systemctl reload nginx
```

### Backend not responding
```bash
# Check if llama-server is running on the port
systemctl status llama-server
systemctl status bielik-server

# Test backend directly
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8081/v1/models
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Client (Continue.dev, Python, curl, etc.)      │
└────────────────┬────────────────────────────────┘
                 │
                 │ HTTP Request
                 │ {"model": "Qwen3-Coder-30B-A3B-Instruct", ...}
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Nginx + Lua (10.0.0.60:80)                     │
│  ┌──────────────────────────────────────┐       │
│  │ 1. Parse JSON body                   │       │
│  │ 2. Extract "model" field             │       │
│  │ 3. Match against patterns            │       │
│  │ 4. Select backend (port)             │       │
│  └──────────────────────────────────────┘       │
└────┬──────────────────────┬─────────────────────┘
     │                      │
     │ model contains       │ model contains
     │ "qwen"              │ "bielik"
     │                      │
     ▼                      ▼
┌─────────────┐        ┌─────────────┐
│ llama-server│        │ llama-server│
│ Qwen3       │        │ Bielik      │
│ (port 8080) │        │ (port 8081) │
└─────────────┘        └─────────────┘
```

## Performance

- **Latency overhead**: ~5-10ms for routing logic
- **Streaming**: Full support for SSE streaming
- **Concurrent requests**: Supports parallel requests to different backends
- **Caching**: Lua shared dictionary for future optimizations

## Security Notes

- Currently configured for local network only (10.0.0.60)
- No authentication required (assumes trusted network)
- For internet exposure:
  - Add SSL/TLS (use certbot)
  - Add API key authentication
  - Use firewall rules (ufw)
  - Rate limiting

## Related Documentation

See also:
- `../systemctl/README.md` - llama-server systemd services
- `../CLAUDE.md` - Hardware and setup overview
- `../LLAMA.CPP_SERVER.md` - llama-server configuration guide
