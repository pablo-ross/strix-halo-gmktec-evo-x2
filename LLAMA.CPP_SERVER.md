# Running llama.cpp Server on Local Network

This guide explains how to make your AMD Strix Halo machine with llama.cpp accessible to other devices on your local network.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Server Setup](#server-setup)
- [Accessing from Other Devices](#accessing-from-other-devices)
- [Using with Common Tools](#using-with-common-tools)
- [Running as a System Service](#running-as-a-system-service)
- [Security Configuration](#security-configuration)
- [Performance Tuning](#performance-tuning)
- [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

---

## Quick Start

**Simplest setup for LAN access:**

```bash
# 1. Start server in container
distrobox enter llama-rocm-7rc-rocwmma

cd ~/llama.cpp
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap

# 2. Find your server IP address
# (On host, open new terminal)
ip addr show | grep "inet " | grep -v 127.0.0.1

# 3. Access from any device on your network
# Open browser to: http://YOUR_SERVER_IP:8080
```

---

## Server Setup

### Basic Server Command

llama.cpp includes a built-in server with an OpenAI-compatible API:

```bash
# Inside the container
cd ~/llama.cpp

./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 4096
```

### Server Parameters Explained

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-m` | Path to model file | `~/models/llama-2-7b.Q4_K_M.gguf` |
| `--host` | Network interface to bind to | `0.0.0.0` (all interfaces) |
| `--port` | Port number | `8080` |
| `-ngl` | Number of layers to offload to GPU | `99` (all) |
| `--no-mmap` | Disable memory mapping (required for GPU) | - |
| `-c` | Context size (tokens) | `4096`, `8192`, `32768` |
| `--parallel` | Number of concurrent requests | `4` |
| `--api-key` | API key for authentication | `your-secret-key` |

### Find Your Server IP Address

**On the host machine:**

```bash
# Show all network interfaces
ip addr show | grep "inet " | grep -v 127.0.0.1

# Or use hostname command
hostname -I
```

Example output:
```
192.168.1.100  # This is your LAN IP
```

---

## Accessing from Other Devices

### Web Interface

The server provides a built-in web UI:

```
http://YOUR_SERVER_IP:8080
```

Open this URL in any browser on your network to chat with the model.

### API Endpoint

The server implements OpenAI-compatible API endpoints:

**Base URL:**
```
http://YOUR_SERVER_IP:8080/v1
```

**Test with curl:**
```bash
curl http://YOUR_SERVER_IP:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Hello! Tell me about yourself."}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

**Check server health:**
```bash
curl http://YOUR_SERVER_IP:8080/health
```

---

## Using with Common Tools

### Python with OpenAI Library

```python
from openai import OpenAI

# Initialize client
client = OpenAI(
    base_url="http://YOUR_SERVER_IP:8080/v1",
    api_key="not-needed"  # No auth by default
)

# Chat completion
response = client.chat.completions.create(
    model="gpt-3.5-turbo",  # Model name doesn't matter
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of France?"}
    ],
    temperature=0.7,
    max_tokens=150
)

print(response.choices[0].message.content)
```

### Python Requests (Raw API)

```python
import requests
import json

url = "http://YOUR_SERVER_IP:8080/v1/chat/completions"
headers = {"Content-Type": "application/json"}

data = {
    "messages": [
        {"role": "user", "content": "Hello!"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
}

response = requests.post(url, headers=headers, data=json.dumps(data))
result = response.json()
print(result['choices'][0]['message']['content'])
```

### JavaScript/Node.js

```javascript
const fetch = require('node-fetch');

async function chat(message) {
  const response = await fetch('http://YOUR_SERVER_IP:8080/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messages: [
        { role: 'user', content: message }
      ],
      temperature: 0.7,
      max_tokens: 100
    })
  });

  const data = await response.json();
  return data.choices[0].message.content;
}

chat("Hello!").then(console.log);
```

### IDE Extensions

**Continue.dev, Cursor, Cody, etc.:**

1. Open extension settings
2. Set API provider to "OpenAI Compatible"
3. Set base URL: `http://YOUR_SERVER_IP:8080/v1`
4. API key: leave empty or set to any value
5. Model name: any value (e.g., "llama-2-7b")

**VSCode with REST Client extension:**

```http
POST http://YOUR_SERVER_IP:8080/v1/chat/completions
Content-Type: application/json

{
  "messages": [
    {"role": "user", "content": "Write a Python function to calculate fibonacci"}
  ],
  "max_tokens": 500
}
```

### LM Studio / Jan.ai

Both can connect to external OpenAI-compatible endpoints:
1. Open settings/preferences
2. Add new server connection
3. URL: `http://YOUR_SERVER_IP:8080`
4. Select the connection when chatting

---

## Running as a System Service

To make the server start automatically on boot and run in the background:

### Create Systemd Service

```bash
# Create service file
sudo nano /etc/systemd/system/llama-server.service
```

**Add this content:**

```ini
[Unit]
Description=llama.cpp Server
After=network.target

[Service]
Type=exec
User=username
WorkingDirectory=/home/username
ExecStart=/home/username/wrappers/llama-server-wrapper.sh
ExecStop=/usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- pkill -TERM llama-server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="XDG_RUNTIME_DIR=/run/user/1000"

# Process management - ensure all processes in cgroup are killed
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
FinalKillSignal=SIGKILL

[Install]
WantedBy=multi-user.target
```

**For larger models or different configurations, adjust:**
- Model path (`-m`)
- Context size (`-c`)
- Port number (`--port`)
- Parallel requests (`--parallel`)

### Create Systemd Wrapper

```bash
# Create service file
nano /home/username/wrappers/llama-server-wrapper.sh
```

**Add this content:**

```bash
#!/bin/bash

# Wrapper script for llama-server in distrobox
# This script is needed because systemd can't execute distrobox enter directly

# Ensure XDG_RUNTIME_DIR is set for podman
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Execute llama-server inside the distrobox container
exec /usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- \
  /home/username/llama.cpp/build/bin/llama-server \
  -m /home/username/models/llama-2-7b-chat.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 8192
```

### Important Notes on Service Configuration

**Why these specific settings?**

When running llama-server inside a distrobox container, standard systemd stop commands may not properly terminate the process. The configuration above includes critical settings to ensure reliable service management:

- **`Type=exec`** - Better process tracking than `Type=simple` for containerized applications
- **`ExecStop`** - Explicitly sends SIGTERM to llama-server inside the container
- **`KillMode=mixed`** - Ensures all processes in the cgroup are terminated, not just the wrapper script
- **`TimeoutStopSec=30`** - Allows 30 seconds for graceful shutdown before forcing termination
- **`FinalKillSignal=SIGKILL`** - Forces cleanup if graceful shutdown fails

Without these settings, running `sudo systemctl stop llama-server` may leave the llama-server process orphaned inside the container, requiring manual cleanup with `pkill`.

**Testing your service:**
```bash
# Test stopping the service
sudo systemctl stop llama-server

# Verify it actually stopped (should show "inactive")
systemctl is-active llama-server

# Check for lingering processes (should return nothing)
ps aux | grep llama-server | grep -v grep
```

### Enable and Start Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable llama-server

# Start service now
sudo systemctl start llama-server

# Check status
sudo systemctl status llama-server
```

### Service Management Commands

```bash
# Stop the server
sudo systemctl stop llama-server

# Restart the server
sudo systemctl restart llama-server

# Disable auto-start on boot
sudo systemctl disable llama-server

# View live logs
sudo journalctl -u llama-server -f

# View last 100 log lines
sudo journalctl -u llama-server -n 100
```

---

## Security Configuration

### Firewall Rules (Recommended)

**Allow access only from local network:**

```bash
# Enable UFW firewall
sudo ufw enable

# Allow SSH (important!)
sudo ufw allow ssh

# Allow llama-server only from local subnet
# Replace 192.168.1.0/24 with your actual subnet
sudo ufw allow from 192.168.1.0/24 to any port 8080

# Check rules
sudo ufw status
```

**Determine your subnet:**
```bash
ip addr show | grep "inet " | grep -v 127.0.0.1
# Look for something like: inet 192.168.1.100/24
# The subnet is: 192.168.1.0/24
```

### API Key Authentication

For additional security, enable API key authentication:

```bash
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --api-key YOUR_SECRET_KEY_HERE \
  -ngl 99 \
  --no-mmap
```

**Generate a secure API key:**
```bash
openssl rand -hex 32
```

**Using the API key from clients:**

```bash
curl http://YOUR_SERVER_IP:8080/v1/chat/completions \
  -H "Authorization: Bearer YOUR_SECRET_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://YOUR_SERVER_IP:8080/v1",
    api_key="YOUR_SECRET_KEY_HERE"
)
```

### HTTPS with Reverse Proxy (Advanced)

For encrypted connections, use nginx as a reverse proxy:

**Install nginx:**
```bash
sudo apt install nginx
```

**Create nginx configuration:**
```bash
sudo nano /etc/nginx/sites-available/llama-server
```

**Add configuration:**
```nginx
server {
    listen 443 ssl;
    server_name llama.local;  # Or use your hostname

    # Self-signed certificate (for development)
    ssl_certificate /etc/ssl/certs/llama-server.crt;
    ssl_certificate_key /etc/ssl/private/llama-server.key;

    # Proxy to llama-server
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;

        # Increase timeouts for long-running requests
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
    }
}
```

**Generate self-signed certificate:**
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/llama-server.key \
  -out /etc/ssl/certs/llama-server.crt
```

**Enable and restart nginx:**
```bash
sudo ln -s /etc/nginx/sites-available/llama-server /etc/nginx/sites-enabled/
sudo nginx -t  # Test configuration
sudo systemctl restart nginx
```

Access via: `https://YOUR_SERVER_IP` or `https://llama.local` (add to /etc/hosts on clients)

---

## Performance Tuning

### Multiple Concurrent Users

**Enable parallel request processing:**

```bash
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 4096 \
  --parallel 4  # Handle up to 4 concurrent requests
```

**Note:** More parallel requests require more GPU memory. Monitor usage with:
```bash
watch -n 1 rocm-smi
```

### Large Context Windows

For long conversations or document analysis:

```bash
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 32768  # 32K token context
```

**Memory impact:**
- 4K context: ~2 GB
- 8K context: ~4 GB
- 16K context: ~8 GB
- 32K context: ~16 GB

With 120GB available, you can easily run 32K+ contexts.

### Batch Size Optimization

For prompt processing performance:

```bash
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  -ngl 99 \
  --no-mmap \
  -c 4096 \
  -b 512  # Batch size (default: 2048)
```

Based on benchmarks, 512 is optimal for this hardware.

### Running Multiple Models

With 120GB memory, you can run multiple models simultaneously:

**Start multiple servers on different ports:**

```bash
# Terminal 1 - Llama 2 7B on port 8080
./build/bin/llama-server \
  -m ~/models/llama-2-7b.Q4_K_M.gguf \
  --host 0.0.0.0 --port 8080 -ngl 99 --no-mmap

# Terminal 2 - Another model on port 8081
./build/bin/llama-server \
  -m ~/models/mistral-7b.Q4_K_M.gguf \
  --host 0.0.0.0 --port 8081 -ngl 99 --no-mmap

# Terminal 3 - Larger model on port 8082
./build/bin/llama-server \
  -m ~/models/llama-70b.Q4_K_M.gguf \
  --host 0.0.0.0 --port 8082 -ngl 99 --no-mmap
```

---

## Monitoring and Troubleshooting

### Check Server Status

**Health endpoint:**
```bash
curl http://localhost:8080/health
```

**Expected response:**
```json
{"status":"ok"}
```

### Monitor GPU Usage

**Real-time monitoring:**
```bash
# In a separate terminal
distrobox enter llama-rocm-7rc-rocwmma
watch -n 1 rocm-smi
```

**Check memory usage:**
```bash
rocm-smi --showmeminfo all
```

### View Server Logs

**If running as systemd service:**
```bash
# Follow logs in real-time
sudo journalctl -u llama-server -f

# Show last 50 lines
sudo journalctl -u llama-server -n 50

# Show logs since last boot
sudo journalctl -u llama-server -b
```

**If running in terminal:**
The server outputs logs directly to stdout/stderr.

### Common Issues

#### Issue: "Cannot connect to server"

**Check if server is running:**
```bash
sudo netstat -tlnp | grep 8080
# or
sudo ss -tlnp | grep 8080
```

**Check firewall:**
```bash
sudo ufw status
```

**Test from server itself:**
```bash
curl http://localhost:8080/health
```

#### Issue: "Connection refused from other devices"

**Verify host binding:**
- Server must use `--host 0.0.0.0`, not `--host localhost` or `--host 127.0.0.1`

**Check firewall rules:**
```bash
sudo ufw status numbered
# Ensure rule allows access from your subnet
```

**Test from another device:**
```bash
# From another computer
ping YOUR_SERVER_IP
telnet YOUR_SERVER_IP 8080
```

#### Issue: "Service won't stop with systemctl stop"

If `sudo systemctl stop llama-server` doesn't actually stop the server:

**Symptom:**
- Service shows as "inactive" but llama-server process is still running
- Port 8080 is still occupied after stopping service
- Need to manually kill the process

**Cause:**
This happens with older service configurations that don't properly handle signals to containerized processes.

**Solution:**
Update your service file to include proper signal handling:

```bash
# Edit your service file
sudo nano /etc/systemd/system/llama-server.service
```

Ensure these settings are present:
```ini
Type=exec  # Not "simple"
ExecStop=/usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- pkill -TERM llama-server
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
FinalKillSignal=SIGKILL
```

Then reload and test:
```bash
sudo systemctl daemon-reload
sudo systemctl stop llama-server
systemctl is-active llama-server  # Should show "inactive"
ps aux | grep llama-server | grep -v grep  # Should return nothing
```

See the [Running as a System Service](#running-as-a-system-service) section for the complete updated service configuration.

#### Issue: "Slow response times"

**Check GPU power state:**
```bash
cat /sys/class/drm/card1/device/power_dpm_force_performance_level
# Should show "auto" or "high"
```

**Set to high performance:**
```bash
echo "high" | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level
```

**Monitor GPU load:**
```bash
watch -n 1 rocm-smi
```

#### Issue: "Out of memory errors"

**Reduce context size:**
```bash
-c 2048  # Instead of 4096 or larger
```

**Reduce parallel requests:**
```bash
--parallel 2  # Instead of 4 or more
```

**Check available memory:**
```bash
distrobox enter llama-rocm-7rc-rocwmma
rocminfo | grep "Size:" | grep -A2 "Pool"
```

### Performance Testing

**Load test with curl:**
```bash
# Simple benchmark
time curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Count from 1 to 100"}],
    "max_tokens": 200
  }'
```

**Concurrent request test:**
```bash
# Install apache bench
sudo apt install apache2-utils

# Test with 10 concurrent requests, 100 total
ab -n 100 -c 10 -p request.json -T 'application/json' \
  http://localhost:8080/v1/chat/completions
```

---

## Advanced Configuration Examples

### Production Setup with Systemd

**Multiple models as services:**

```bash
# Create service for each model
sudo nano /etc/systemd/system/llama-7b.service
sudo nano /etc/systemd/system/llama-70b.service
```

**Service file for 7B model (port 8080):**
```ini
[Unit]
Description=llama.cpp Server - Llama 2 7B
After=network.target

[Service]
Type=exec
User=username
WorkingDirectory=/home/username
ExecStart=/usr/bin/distrobox enter llama-rocm-7rc-rocwmma -- /home/username/llama.cpp/build/bin/llama-server -m /home/username/models/llama-2-7b.Q4_K_M.gguf --host 0.0.0.0 --port 8080 -ngl 99 --no-mmap -c 4096 --parallel 4
ExecStop=/usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- pkill -TERM llama-server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="XDG_RUNTIME_DIR=/run/user/1000"

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
FinalKillSignal=SIGKILL

[Install]
WantedBy=multi-user.target
```

**Service file for 70B model (port 8081):**
```ini
[Unit]
Description=llama.cpp Server - Llama 70B
After=network.target

[Service]
Type=exec
User=username
WorkingDirectory=/home/username
ExecStart=/usr/bin/distrobox enter llama-rocm-7rc-rocwmma -- /home/username/llama.cpp/build/bin/llama-server -m /home/username/models/llama-70b.Q4_K_M.gguf --host 0.0.0.0 --port 8081 -ngl 99 --no-mmap -c 8192 --parallel 2
ExecStop=/usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- pkill -TERM llama-server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="XDG_RUNTIME_DIR=/run/user/1000"

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
FinalKillSignal=SIGKILL

[Install]
WantedBy=multi-user.target
```

**Enable both:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable llama-7b llama-70b
sudo systemctl start llama-7b llama-70b
```

### Load Balancer for High Availability

If you want to run multiple instances and load balance between them, use nginx:

```nginx
upstream llama_backend {
    least_conn;  # Use least connections algorithm
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
    server 127.0.0.1:8082;
}

server {
    listen 80;
    server_name llama.local;

    location / {
        proxy_pass http://llama_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
    }
}
```

---

## API Reference

### Endpoints

**Base URL:** `http://YOUR_SERVER_IP:8080`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Server health check |
| `/v1/models` | GET | List available models |
| `/v1/chat/completions` | POST | Chat completion (streaming supported) |
| `/v1/completions` | POST | Text completion |
| `/v1/embeddings` | POST | Generate embeddings |

### Request Examples

**Chat Completion (OpenAI format):**
```json
POST /v1/chat/completions
{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 100,
  "stream": false
}
```

**Streaming Response:**
```json
POST /v1/chat/completions
{
  "messages": [
    {"role": "user", "content": "Write a story"}
  ],
  "stream": true
}
```

**Text Completion:**
```json
POST /v1/completions
{
  "prompt": "Once upon a time",
  "max_tokens": 100,
  "temperature": 0.7
}
```

### Response Format

**Chat Completion Response:**
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1699999999,
  "model": "gpt-3.5-turbo",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I help you today?"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 20,
    "total_tokens": 30
  }
}
```

---

## Summary

You now have multiple options for making your llama.cpp setup accessible on your local network:

1. **Quick Start:** Simple server command for immediate access
2. **System Service:** Persistent server that starts automatically
3. **Security:** Firewall rules and API key authentication
4. **Integration:** Works with OpenAI-compatible clients and tools
5. **Monitoring:** Health checks and logging

Your 120GB GPU memory makes this setup ideal for:
- Serving multiple models simultaneously
- Handling large context windows (32K+ tokens)
- Supporting multiple concurrent users
- Running production-grade LLM services

**Next Steps:**
- Start with the quick start to test functionality
- Set up systemd service for persistence
- Configure firewall for security
- Integrate with your preferred tools and IDEs
