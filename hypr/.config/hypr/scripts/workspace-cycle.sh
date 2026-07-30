#!/usr/bin/env bash
# ALT+Tab: cycle to the next workspace pinned to whichever monitor
# currently has focus (only "next" is bound; "prev" is supported here for
# scripting/testing but has no keybind). Hyprland's native `workspace, +1`
# dispatcher cycles by global workspace ID and crosses monitor boundaries
# once it runs past the focused monitor's range (confirmed live: stepping
# +1 five times from DP-4's workspace 2 walked focus straight onto
# HDMI-A-3's workspace 6/7) — not what "cycle workspaces on this monitor"
# means, so this computes the wrap-around manually instead.
set -euo pipefail

DIRECTION="${1:?Usage: workspace-cycle.sh next|prev}"

FOCUSED_MONITOR="$(hyprctl activeworkspace -j | jq -r '.monitor')"
CURRENT_ID="$(hyprctl activeworkspace -j | jq -r '.id')"

# Workspace IDs to cycle: the statically pinned ones (workspacerules) plus
# any currently-live workspace on this monitor (covers ones created on the
# fly by new-workspace.sh, which aren't in workspacerules at all).
mapfile -t IDS < <( {
  hyprctl workspacerules -j \
    | jq -r --arg mon "${FOCUSED_MONITOR}" '.[] | select(.monitor == $mon) | .workspaceString | tonumber'
  hyprctl workspaces -j \
    | jq -r --arg mon "${FOCUSED_MONITOR}" '.[] | select(.monitor == $mon) | .id'
} | sort -n -u)

[[ "${#IDS[@]}" -gt 0 ]] || exit 0

# Index of the current workspace within this monitor's pinned range.
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

hyprctl dispatch workspace "${IDS[$NEXT_IDX]}"
