#!/usr/bin/env bash
# Shared host picker for the Claude and Qwen scratchpads. Run at the start
# of every session (see toggle-claude-scratchpad.sh / toggle-qwen-scratchpad.sh)
# so the AI can be pointed at any machine, not just ollama-host. Prints
# either "local" or "user@host" on stdout and exits 0, or exits 1 with
# nothing printed if the user backed out (Esc in fzf).
#
# Static hosts are hand-maintained here (Proxmox itself and pre-existing
# guests we didn't create have no discoverable IP/user via the API).
# Dashboard-managed guests (on-demand VMs from create_vm.sh) are listed
# dynamically via proxmox_stats.py + their guest-agent IP, same lookup
# ssh-vm.sh already does.
set -euo pipefail

STATS="$("${HOME}/.local/bin/proxmox_stats.py" 2>/dev/null || echo '{"status":"error"}')"
STATUS="$(jq -r '.status' <<< "$STATS" 2>/dev/null || echo error)"

declare -a LABELS
declare -a TARGETS

LABELS+=("Local (this desktop)")
TARGETS+=("local")

LABELS+=("Ollama-host (192.168.1.97)")
TARGETS+=("rafael@192.168.1.97")

LABELS+=("Mineserver (192.168.1.91)")
TARGETS+=("mineserver@192.168.1.91")

LABELS+=("Proxmox host (192.168.1.71)")
TARGETS+=("root@192.168.1.71")

if [[ "${STATUS}" == "ok" ]]; then
  while IFS=$'\t' read -r VMID NAME; do
    [[ -z "${VMID}" ]] && continue
    IP_RESULT="$("${HOME}/.local/bin/vm_ops.py" ip "${VMID}" 2>/dev/null || true)"
    if [[ "${IP_RESULT}" == OK* ]]; then
      IP="${IP_RESULT#OK }"
      LABELS+=("${NAME} (${IP}, on-demand)")
      TARGETS+=("ubuntu@${IP}")
    fi
  done < <(jq -r '.guests[] | select(.dashboard_managed == true and .status == "running") | "\(.vmid)\t\(.name)"' <<< "$STATS")
fi

SELECTION="$(printf '%s\n' "${LABELS[@]}" | fzf --prompt="Work where? " --height=40% --layout=reverse)"
if [[ -z "${SELECTION}" ]]; then
  exit 1
fi

for i in "${!LABELS[@]}"; do
  if [[ "${LABELS[$i]}" == "${SELECTION}" ]]; then
    echo "${TARGETS[$i]}"
    exit 0
  fi
done

exit 1
