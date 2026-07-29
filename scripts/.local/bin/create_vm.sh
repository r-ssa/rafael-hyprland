#!/usr/bin/env bash
# "New VM" flow (Phase 5): rofi prompt -> explicit confirm -> clone -> start.
# There is no path from prompt to clone without the confirm step below.
set -euo pipefail

VM_OPS="${HOME}/.local/bin/vm_ops.py"

notify() {
  notify-send -a "Proxmox Dashboard" "$1" "$2"
}

NAME="$(rofi -dmenu -p "New VM name:" -lines 0)"
if [[ -z "${NAME}" ]]; then
  exit 0
fi

# Keep it simple and safe for a Proxmox VM name (DNS-label-ish).
if ! [[ "${NAME}" =~ ^[a-zA-Z0-9-]+$ ]]; then
  notify "Invalid name" "VM names can only contain letters, digits, and hyphens."
  exit 1
fi

NEWID_LINE="$("${VM_OPS}" nextid)"
if [[ "${NEWID_LINE}" != OK* ]]; then
  notify "Failed to get next VM ID" "${NEWID_LINE#ERROR }"
  exit 1
fi
NEWID="${NEWID_LINE#OK }"

CHOICE="$(printf 'Create\nCancel' | rofi -dmenu -p "Create VM '${NAME}' (id ${NEWID}, 2 cores / 2048MB) from template?" -lines 2)"
if [[ "${CHOICE}" != "Create" ]]; then
  exit 0
fi

notify "Creating VM ${NAME}" "Cloning from template, this can take a minute..."
CLONE_RESULT="$("${VM_OPS}" clone "${NEWID}" "${NAME}" 2>&1)"
if [[ "${CLONE_RESULT}" != OK* ]]; then
  notify "VM creation failed" "${CLONE_RESULT#ERROR }"
  exit 1
fi

START_RESULT="$("${VM_OPS}" start "${NEWID}" 2>&1)"
if [[ "${START_RESULT}" != OK* ]]; then
  notify "VM created but failed to start" "${CLONE_RESULT#OK }. ${START_RESULT#ERROR }"
  exit 1
fi

notify "VM created" "${CLONE_RESULT#OK }, and started."
