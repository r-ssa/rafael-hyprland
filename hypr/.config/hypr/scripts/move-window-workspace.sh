#!/usr/bin/env bash
# SUPER+scroll: move the active window to the next/prev workspace on the
# focused monitor and follow it there (movetoworkspace switches focus
# too, unlike movetoworkspacesilent) — meant to be scrolled while you're
# mid-drag on that window via the SUPER+left-click movewindow bind.
# Reuses workspace-cycle.sh's monitor-scoped id list so this never walks
# off the focused monitor's range, same reasoning as that script.
set -euo pipefail

DIRECTION="${1:?Usage: move-window-workspace.sh next|prev}"

FOCUSED_MONITOR="$(hyprctl activeworkspace -j | jq -r '.monitor')"
CURRENT_ID="$(hyprctl activeworkspace -j | jq -r '.id')"

mapfile -t IDS < <( {
  hyprctl workspacerules -j \
    | jq -r --arg mon "${FOCUSED_MONITOR}" '.[] | select(.monitor == $mon) | .workspaceString | tonumber'
  hyprctl workspaces -j \
    | jq -r --arg mon "${FOCUSED_MONITOR}" '.[] | select(.monitor == $mon) | .id'
} | sort -n -u)

[[ "${#IDS[@]}" -gt 0 ]] || exit 0

CURRENT_IDX=-1
for i in "${!IDS[@]}"; do
  [[ "${IDS[$i]}" == "${CURRENT_ID}" ]] && CURRENT_IDX="$i"
done
[[ "${CURRENT_IDX}" -ge 0 ]] || CURRENT_IDX=0

COUNT="${#IDS[@]}"
if [[ "${DIRECTION}" == "next" ]]; then
  NEXT_IDX=$(( (CURRENT_IDX + 1) % COUNT ))
else
  NEXT_IDX=$(( (CURRENT_IDX - 1 + COUNT) % COUNT ))
fi

hyprctl dispatch movetoworkspace "${IDS[$NEXT_IDX]}"
