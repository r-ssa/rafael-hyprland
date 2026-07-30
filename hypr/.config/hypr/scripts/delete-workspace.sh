#!/usr/bin/env bash
# ALT+CTRL+Tab: close every window on the current workspace and switch
# to the previous workspace on this monitor first, then close — so focus
# has already moved away by the time the windows disappear. A pinned 1-9
# workspace just goes back to empty (persistent:true keeps it around); a
# workspace created by new-workspace.sh actually vanishes once its last
# window closes, since those aren't persistent.
set -euo pipefail

CURRENT_ID="$(hyprctl activeworkspace -j | jq -r '.id')"

~/.config/hypr/scripts/workspace-cycle.sh prev

mapfile -t ADDRS < <(hyprctl clients -j \
  | jq -r --argjson id "${CURRENT_ID}" '.[] | select(.workspace.id == $id) | .address')

for addr in "${ADDRS[@]}"; do
  hyprctl dispatch closewindow "address:${addr}"
done
