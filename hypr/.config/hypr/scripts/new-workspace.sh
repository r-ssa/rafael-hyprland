#!/usr/bin/env bash
# SHIFT+ALT+Tab: create a fresh, empty workspace and switch to it, always
# on DP-4 (the main monitor) — workspaces are DP-4-exclusive for now, no
# dynamic workspaces on the secondary monitor (HDMI-A-3). Confirmed live
# that dispatching `workspace <id>` for a brand-new id does NOT reliably
# land on whichever monitor currently has focus (it kept landing on
# HDMI-A-3 regardless), so this focuses DP-4 first and moves the new
# workspace there explicitly as a backstop rather than trusting that.
# The id picked is one past the highest workspace id that exists
# anywhere, so it can never collide with the pinned 1-9 range or another
# dynamically-created workspace.
# workspace-cycle.sh picks these up automatically since it reads live
# workspaces on the monitor, not just the static pinned list.
set -euo pipefail

# Same lock as workspace-cycle.sh/move-window-workspace.sh — this reads
# "highest workspace id" and could compute a stale/colliding id if it
# raced one of those scripts mutating workspace state at the same time.
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-workspace-ops.lock"
exec 200>"${LOCKFILE}"
flock -n 200 || exit 0

MAX_ID="$(hyprctl workspaces -j | jq -r '[.[].id] | max // 0')"
NEW_ID=$(( MAX_ID + 1 ))

hyprctl dispatch focusmonitor DP-4
hyprctl dispatch workspace "${NEW_ID}"
hyprctl dispatch moveworkspacetomonitor "${NEW_ID}" DP-4
