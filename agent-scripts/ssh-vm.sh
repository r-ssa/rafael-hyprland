#!/usr/bin/env bash
# Pick a Proxmox guest and SSH into it. Meant to run inside the Claude Code
# scratchpad terminal (see toggle-claude-scratchpad.sh) so a new session can
# jump straight into a VM.
#
# - Guests the dashboard created (tagged dashboard-managed) are reachable
#   automatically: IP via the QEMU guest agent, user "ubuntu", the dedicated
#   key at ~/.ssh/proxmox-guest-key (see bootstrap.sh's guest-key setup).
# - Any other guest (e.g. mineserver, hyprland-test) needs a manual entry in
#   ~/.config/hyprland-rice/vm-ssh-hosts.conf — we have no way to discover
#   credentials for VMs we didn't create.
set -euo pipefail

HOSTS_FILE="${HOME}/.config/hyprland-rice/vm-ssh-hosts.conf"
VM_OPS="${HOME}/.local/bin/vm_ops.py"
GUEST_KEY="${HOME}/.ssh/proxmox-guest-key"

STATS="$("${HOME}/.local/bin/proxmox_stats.py")"
STATUS="$(jq -r '.status' <<< "$STATS")"
if [[ "${STATUS}" != "ok" ]]; then
  echo "Can't reach Proxmox: $(jq -r '.message' <<< "$STATS")" >&2
  exit 1
fi

SELECTION="$(jq -r '.guests[] | "\(.name) (\(.vmid), \(.status))"' <<< "$STATS" | fzf --prompt="SSH into which VM? ")"
if [[ -z "${SELECTION}" ]]; then
  exit 0
fi

VMID="$(sed -E 's/.*\(([0-9]+),.*/\1/' <<< "$SELECTION")"
NAME="$(jq -r --arg vmid "$VMID" '.guests[] | select(.vmid == ($vmid | tonumber)) | .name' <<< "$STATS")"
MANAGED="$(jq -r --arg vmid "$VMID" '.guests[] | select(.vmid == ($vmid | tonumber)) | .dashboard_managed' <<< "$STATS")"

if [[ "${MANAGED}" == "true" ]]; then
  if [[ ! -f "${GUEST_KEY}" ]]; then
    echo "No guest SSH key at ${GUEST_KEY} — run bootstrap.sh to set it up." >&2
    exit 1
  fi
  echo "Looking up ${NAME}'s IP via the guest agent (can take ~30s after boot)..."
  IP_RESULT="$("${VM_OPS}" ip "${VMID}")"
  if [[ "${IP_RESULT}" != OK* ]]; then
    echo "${IP_RESULT#ERROR }" >&2
    exit 1
  fi
  IP="${IP_RESULT#OK }"
  exec ssh -i "${GUEST_KEY}" -o StrictHostKeyChecking=accept-new "ubuntu@${IP}"
fi

if [[ -f "${HOSTS_FILE}" ]]; then
  ENTRY="$(awk -v name="${NAME}" '$1 == name {print $2}' "${HOSTS_FILE}")"
  if [[ -n "${ENTRY}" ]]; then
    exec ssh "${ENTRY}"
  fi
fi

echo "No known SSH target for '${NAME}' — add a line to ${HOSTS_FILE}:" >&2
echo "  ${NAME} user@host" >&2
exit 1
