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

# Holding Tab down fires key-repeat, which spawns a new instance of this
# script on every repeat — with no lock, overlapping instances all read
# "current workspace" before any of them dispatch, so they can compute
# conflicting targets and the whole thing skips/jumps erratically instead
# of cycling one step at a time. flock -n makes each repeat that lands
# while a previous one is still running a no-op instead of racing it.
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-workspace-ops.lock"
exec 200>"${LOCKFILE}"
flock -n 200 || exit 0

DIRECTION="${1:?Usage: workspace-cycle.sh next|prev}"

FOCUSED_MONITOR="$(hyprctl activeworkspace -j | jq -r '.monitor')"
CURRENT_ID="$(hyprctl activeworkspace -j | jq -r '.id')"

# Cycle ONLY workspaces that actually exist right now on this monitor.
# Deliberately NOT unioned with workspacerules: those pins (1-5 on DP-4,
# 6-9 on HDMI-A-3) exist purely to bind an id to a monitor *if* that
# workspace gets created — they are not a list of workspaces you have.
# Including them meant cycling from a live workspace 2 targeted workspace
# 3, which didn't exist, so Hyprland created it on the spot: alt-tab
# appeared to "make a new workspace," and you had to keep pressing
# through the empty 3/4 to reach real content on 5.
#
# Special workspaces (scratchpads, e.g. the Claude Code toggle — always
# negative ids) are excluded too: `.monitor` on a special workspace
# matches whichever real monitor it's currently shown on, so without the
# id >= 0 filter the scratchpad joined the cycle, and since -98 sorts
# before every real id, wrapping past the last workspace landed there
# instead of on the first real one.
mapfile -t IDS < <(hyprctl workspaces -j \
  | jq -r --arg mon "${FOCUSED_MONITOR}" '.[] | select(.monitor == $mon and .id >= 0) | .id' \
  | sort -n -u)

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
