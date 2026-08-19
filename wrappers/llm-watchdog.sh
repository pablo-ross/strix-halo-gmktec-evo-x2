#!/bin/bash
# ==============================================================================
# llm-watchdog.sh — detect silent output corruption in llama-server instances
# ==============================================================================
# Background: llama.cpp build 666f8898a corrupts output on this hardware. It hit
# Qwen3-Coder loudly ("//////...") on 2026-08-17 and Bielik quietly on 2026-08-18
# ("cztefyry" for "cztery", plus verbatim prompt regurgitation and leakage of KV
# state from unrelated earlier requests). Both are clean on 4d828bd1a, which is
# what both wrappers are pinned to as of 2026-08-19. See LLAMA_ISSUES_SUMMARY.md.
#
# PROBE DESIGN (revised 2026-08-19). The original probe was "List three colours."
# plus a "<=3 distinct characters" degeneracy test. It never fired once in 46h
# against a provably broken Bielik, for two independent reasons:
#   1. Too short. Corruption needed ~1600+ prompt tokens to appear; a 10-token
#      prompt is always clean even on a broken server.
#   2. Too lax. "Dwa plus dwa to cztefyry." has many distinct characters and
#      sails through a distinct-character test.
# So the probe now sends a ~2000-token prompt and checks for an EXACT expected
# answer (needle retrieval), which catches subtle corruption, not just collapse.
#
# Two consecutive failures are required before restarting, so a transient blip
# does not cause restart churn.
# ==============================================================================
LOG="/home/mornel/.local/log/llm-watchdog.log"
mkdir -p "$(dirname "$LOG")"

NEEDLE="7391"

probe() { # $1=port -> reply text on stdout, empty on transport failure
  python3 - "$1" <<'PY'
import json, sys, urllib.request
port = sys.argv[1]
# ~2000 tokens of filler with a single needle buried in the middle.
lines = [f"record {i:04d}: status=ok latency=12ms region=eu-central" for i in range(200)]
lines.insert(100, "ACCESS-CODE: 7391")
body = {"model": "probe", "max_tokens": 24, "temperature": 0,
        "messages": [
            {"role": "system", "content": "You answer with the fewest words possible.\n" + "\n".join(lines)},
            {"role": "user", "content": "What is the ACCESS-CODE in the text above? Reply with the digits only."}]}
try:
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    print(json.load(urllib.request.urlopen(req, timeout=180))["choices"][0]["message"]["content"])
except Exception:
    pass
PY
}

is_bad() { # $1=text -> exit 0 if the reply is corrupt
  python3 -c '
import re, sys
t, needle = sys.argv[1].strip(), sys.argv[2]
body = "".join(t.split())
if len(t) > 10 and len(set(body)) <= 3:   # outright degeneracy ("//////")
    sys.exit(0)
if needle not in t:                        # wrong/garbled answer
    sys.exit(0)
if len(body) > 40:                         # correct needle but rambling = regurgitation
    sys.exit(0)
sys.exit(1)
' "$1" "$2"
}

snapshot() { # $1=reason $2=port $3=label $4=reply
  local pid
  pid=$(pgrep -f "llama-server.*port $2" | head -1)
  {
    echo "---------------------------------------------------------------"
    echo "[$(date '+%F %T')] CORRUPT OUTPUT on port $2 ($3)"
    echo "reason:    $1"
    echo "reply:     $(printf '%s' "$4" | head -c 300)"
    if [ -n "$pid" ]; then
      echo "binary:    $(readlink -f "/proc/$pid/exe" 2>/dev/null)"
      echo "uptime:    $(ps -o etime= -p "$pid" | tr -d ' ')"
      echo "rss:       $(ps -o rss= -p "$pid" | tr -d ' ') KB"
    fi
    echo "mem:       $(free -m | awk '/^Mem:/{printf "%d used / %d total / %d avail (MiB)", $3, $2, $7}')"
    echo "swap:      $(free -m | awk '/^Swap:/{printf "%d / %d MiB", $3, $2}')"
    echo "psi:       $(tr '\n' ' ' < /proc/pressure/memory)"
    echo "gtt_used:  $(cat /sys/class/drm/card0/device/mem_info_gtt_used 2>/dev/null)"
    echo "dpm:       $(cat /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null)"
    echo "dmesg:     $(dmesg -T 2>/dev/null | grep -iE 'amdgpu|ring|reset|fault' | tail -3 | tr '\n' '|')"
  } >> "$LOG"
}

check() { # $1=port $2=unit $3=label
  local out out2
  out="$(probe "$1")"
  [ -z "$out" ] && return 0                 # transport failure or busy: not our signal
  is_bad "$out" "$NEEDLE" || return 0        # healthy
  sleep 20
  out2="$(probe "$1")"
  [ -z "$out2" ] && return 0
  is_bad "$out2" "$NEEDLE" || return 0       # transient, recovered on retry
  snapshot "two consecutive corrupt probes" "$1" "$3" "$out2"
  echo "[$(date '+%F %T')] restarting $2" >> "$LOG"
  systemctl restart "$2"
}

check 8080 llama-server.service  qwen
check 8081 bielik-server.service bielik
