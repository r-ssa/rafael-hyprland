#!/usr/bin/env bash
# Delete-VM flow (Phase 5): called with a vmid + name, confirms via rofi
# before stopping (if needed) and destroying — same "no single click
# destroys anything" rule as create_vm.sh.
set -euo pipefail

VM_OPS="${HOME}/.local/bin/vm_ops.py"
VMID="$1"
NAME="${2:-vmid ${VMID}}"

notify() {
  notify-send -a "Proxmox Dashboard" "$1" "$2"
}

CHOICE="$(printf 'Delete\nCancel' | rofi -dmenu -p "Permanently delete '${NAME}' (${VMID})? This cannot be undone." -lines 2)"
if [[ "${CHOICE}" != "Delete" ]]; then
  exit 0
fi

"${VM_OPS}" stop "${VMID}" >/dev/null 2>&1 || true
RESULT="$("${VM_OPS}" destroy "${VMID}" 2>&1)"
if [[ "${RESULT}" != OK* ]]; then
  notify "Delete failed" "${RESULT#ERROR }"
  exit 1
fi

notify "VM deleted" "${RESULT#OK }"
