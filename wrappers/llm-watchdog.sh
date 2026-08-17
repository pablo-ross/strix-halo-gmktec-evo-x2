#!/bin/bash
# ==============================================================================
# llm-watchdog.sh — detect silent output corruption in llama-server instances
# ==============================================================================
# Background: on 2026-08-17 the Qwen3-Coder-Next server twice began emitting
# degenerate output ("//////...") after ~20-30 min of mostly-idle uptime. No
# errors were logged, throughput stayed normal (42 t/s), and a restart cleared
# it. Cause still unknown. This probes each backend, records full system state
# on detection (so the next occurrence is diagnosable rather than reconstructed
# after the fact), and restarts the affected unit.
#
# Degeneracy test is model-agnostic: a reply longer than 10 chars containing 3
# or fewer distinct non-whitespace characters. Requires two consecutive failed
# probes before restarting, so a transient blip does not cause restart churn.
# ==============================================================================
LOG="/home/mornel/.local/log/llm-watchdog.log"
PROMPT="List three colours."

probe() { # $1=port -> reply text on stdout, empty on transport failure
  curl -s --max-time 120 "http://127.0.0.1:$1/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":40,\"temperature\":0}" \
    2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["choices"][0]["message"]["content"])
except Exception:
    pass
' 2>/dev/null
}

is_degenerate() { # $1=text -> exit 0 if degenerate
  python3 -c '
import sys
t = sys.argv[1].strip()
body = "".join(t.split())
sys.exit(0 if len(t) > 10 and len(set(body)) <= 3 else 1)
' "$1"
}

snapshot() { # $1=reason $2=port $3=label
  local pid
  pid=$(pgrep -f "llama-server.*port $2" | head -1)
  {
    echo "---------------------------------------------------------------"
    echo "[$(date '+%F %T')] DEGENERATE OUTPUT on port $2 ($3)"
    echo "reason:    $1"
    if [ -n "$pid" ]; then
      echo "uptime:    $(ps -o etime= -p "$pid" | tr -d ' ')"
      echo "rss:       $(ps -o rss= -p "$pid" | tr -d ' ') KB"
    fi
    echo "mem:       $(free -m | awk '/^Mem:/{printf "%d used / %d total / %d avail (MiB)", $3, $2, $7}')"
    echo "swap:      $(free -m | awk '/^Swap:/{printf "%d / %d MiB", $3, $2}')"
    echo "psi:       $(tr '\n' ' ' < /proc/pressure/memory)"
    echo "gtt_used:  $(cat /sys/class/drm/card0/device/mem_info_gtt_used 2>/dev/null)"
    echo "dpm:       $(cat /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null)"
    echo "gpu_clk:   $(cat /sys/class/drm/card0/device/pp_dpm_sclk 2>/dev/null | tr '\n' ' ')"
    echo "dmesg:     $(dmesg -T 2>/dev/null | grep -iE 'amdgpu|ring|reset|fault' | tail -3 | tr '\n' '|')"
  } >> "$LOG"
}

check() { # $1=port $2=unit $3=label
  local out out2
  out="$(probe "$1")"
  [ -z "$out" ] && return 0                # transport failure or busy: not our signal
  is_degenerate "$out" || return 0         # healthy
  sleep 20
  out2="$(probe "$1")"
  [ -z "$out2" ] && return 0
  is_degenerate "$out2" || return 0         # transient, recovered on retry
  snapshot "two consecutive degenerate probes" "$1" "$3"
  echo "[$(date '+%F %T')] restarting $2" >> "$LOG"
  systemctl restart "$2"
}

check 8080 llama-server.service  qwen
check 8081 bielik-server.service bielik
