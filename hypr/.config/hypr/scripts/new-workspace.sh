#!/usr/bin/env bash
# SHIFT+ALT+Tab: create a fresh, empty workspace and switch to it on
# whichever monitor currently has focus. Dispatching `workspace <id>` for
# an id that doesn't exist yet creates it on the focused monitor (no
# workspace= pin needed) — the id picked is one past the highest workspace
# id that exists anywhere, so it can never collide with the pinned 1-9
# range or another monitor's dynamic workspaces.
# workspace-cycle.sh picks these up automatically since it reads live
# workspaces on the monitor, not just the static pinned list.
set -euo pipefail

MAX_ID="$(hyprctl workspaces -j | jq -r '[.[].id] | max // 0')"
NEW_ID=$(( MAX_ID + 1 ))

hyprctl dispatch workspace "${NEW_ID}"
