#!/usr/bin/env bash
# `ai-status` — gathers local system + Proxmox state and asks Claude Code
# for a one-shot summary. Aliased in ~/.bashrc (see bootstrap.sh).
set -euo pipefail

SUMMARY="$(cat <<EOF
Host: $(hostname)
Uptime: $(uptime -p)
Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')
Disk (/): $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')
Load average: $(cut -d' ' -f1-3 /proc/loadavg)

Proxmox:
$(~/.local/bin/proxmox_stats.py 2>/dev/null | jq -r '
  if .status == "ok" then
    "Node: \(.node.cpu_pct)% cpu, \(.node.mem_pct)% mem, \(.node.disk_pct)% disk\n" +
    (.guests | map("  - \(.name) (\(.vmid)): \(.status), \(.cpu_pct)% cpu, \(.mem_pct)% mem") | join("\n"))
  else
    "unreachable: \(.message)"
  end
')
EOF
)"

claude -p "Here is my current system and homelab status. Give me a brief (3-5 bullet) health summary, calling out anything that looks wrong (high usage, a guest that's down, etc.):

${SUMMARY}"
