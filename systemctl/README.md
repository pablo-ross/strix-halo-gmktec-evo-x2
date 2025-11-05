# llama.cpp Systemd Service Configuration

Production-ready systemd service files for running multiple llama-server instances on AMD Strix Halo with ROCm.

## Files

- `llama-server.service` - Qwen3-Coder-30B service (port 8080)
- `bielik-server.service` - Bielik-11B service (port 8081)
- `qwen3-coder-server.sh` - Wrapper script for Qwen3-Coder-30B
- `bielik-11b-server.sh` - Wrapper script for Bielik-11B

## Installation

### 1. Copy wrapper scripts

```bash
mkdir -p ~/wrappers
cp qwen3-coder-server.sh ~/wrappers/
cp bielik-11b-server.sh ~/wrappers/
chmod +x ~/wrappers/*.sh
```

### 2. Update service files

Edit the `.service` files and replace `username` with your actual username:

```bash
sed -i "s/username/$(whoami)/g" llama-server.service
sed -i "s/username/$(whoami)/g" bielik-server.service
```

### 3. Install service files

```bash
sudo cp llama-server.service /etc/systemd/system/
sudo cp bielik-server.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### 4. Enable user lingering (CRITICAL!)

This is required for distrobox/podman containers to work with systemd services:

```bash
sudo loginctl enable-linger $(id -u)
```

Verify it's enabled:

```bash
loginctl show-user $(whoami) | grep Linger
# Should output: Linger=yes
```

### 5. Enable and start services

```bash
# Enable auto-start on boot
sudo systemctl enable llama-server bielik-server

# Start services now
sudo systemctl start llama-server bielik-server

# Wait ~20 seconds for models to load, then check status
sleep 20
sudo systemctl status llama-server bielik-server
```

### 6. Test endpoints

```bash
curl http://localhost:8080/health  # Qwen3-Coder-30B
curl http://localhost:8081/health  # Bielik-11B
```

## Service Management

```bash
# Start services
sudo systemctl start llama-server
sudo systemctl start bielik-server

# Stop services
sudo systemctl stop llama-server
sudo systemctl stop bielik-server

# Restart services
sudo systemctl restart llama-server
sudo systemctl restart bielik-server

# View logs
sudo journalctl -u llama-server -f
sudo journalctl -u bielik-server -f

# Check status
sudo systemctl status llama-server
sudo systemctl status bielik-server
```

## Key Features

### Port-Based Process Management

The `ExecStop` directive uses `lsof` to identify the process by port number:

```ini
ExecStop=/usr/local/bin/distrobox enter llama-rocm-7rc-rocwmma -- /bin/bash -c "/usr/sbin/lsof -ti:PORT | xargs -r kill -TERM"
```

This ensures:
- Only the specific llama-server instance is stopped
- No orphaned processes are left running
- Multiple servers can run in the same container without conflicts

### Why This Approach?

1. **Container isolation**: Both servers run in the same distrobox container
2. **Process identification**: Using `pkill llama-server` would kill ALL servers
3. **Port-based targeting**: `lsof -ti:PORT` identifies the exact process
4. **Clean shutdown**: SIGTERM allows graceful shutdown

## Troubleshooting

### Services fail to start after reboot

**Symptom**: Services show as "failed" with cgroup errors

**Solution**: Enable user lingering:
```bash
sudo loginctl enable-linger $(id -u)
```

### Service won't stop properly

**Symptom**: `systemctl stop` returns but server keeps running

**Check**:
1. Verify `lsof` exists in container:
   ```bash
   distrobox enter llama-rocm-7rc-rocwmma -- which lsof
   # Should output: /usr/sbin/lsof
   ```

2. Check for orphaned processes:
   ```bash
   ps aux | grep llama-server
   ```

3. Manually kill if needed:
   ```bash
   pkill -f 'llama-server.*PORT'
   ```

### Both servers stop when stopping one

**Cause**: Old service configuration using `pkill llama-server`

**Solution**: Update to the port-based ExecStop configuration in these files

## Technical Notes

### Type=simple vs Type=exec

- Using `Type=simple` because distrobox-enter doesn't exec, it spawns
- This prevents systemd from thinking the service failed immediately

### TimeoutStopSec=10

- 10 seconds is sufficient for llama-server graceful shutdown
- Reduces wait time during restarts

### XDG_RUNTIME_DIR

- Required for podman/distrobox to work with user session
- Set to `/run/user/1000` (or your UID)

## Model Configuration

### Qwen3-Coder-30B (Port 8080)
- Model: Qwen3-Coder-30B-A3B-Instruct-UD-Q8_K_XL.gguf
- Context: 128K tokens
- Reasoning: DeepSeek-style enabled
- Parallel slots: 4
- Memory: ~18-20GB

### Bielik-11B (Port 8081)
- Model: Bielik-11B-v2.6-Instruct.Q8_0.gguf
- Context: 64K tokens
- Language: Polish
- Parallel slots: 6
- Memory: ~11-12GB

Both models fit comfortably in the 120GB GTT memory available on Strix Halo.

## Firewall Configuration

To allow access from local network:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 8080
sudo ufw allow from 192.168.1.0/24 to any port 8081
```

## OpenAI API Compatibility

Both servers implement OpenAI-compatible API:

```bash
# Qwen3-Coder-30B
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "temperature": 0.7,
    "max_tokens": 100
  }'

# Bielik-11B
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Cześć!"}],
    "temperature": 0.2,
    "max_tokens": 100
  }'
```
