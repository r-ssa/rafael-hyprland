#!/usr/bin/env bash
# Toggles a Hyprland special workspace running Claude Code in a terminal.
# Bound to SUPER+F1 in hyprland.conf. On first spawn, launch-claude-session.sh
# asks which machine to work on (see pick-target.sh) before running claude,
# local or over SSH. Just toggles visibility after that (see windowrule in
# hyprland.conf for how the "claude-scratchpad" class window gets pinned to
# this workspace).
set -euo pipefail

CLASS="claude-scratchpad"

if hyprctl clients -j | jq -e --arg c "$CLASS" '[.[] | select(.class == $c)] | length > 0' >/dev/null; then
  hyprctl dispatch togglespecialworkspace claude
else
  kitty --class "$CLASS" -e ~/agent-scripts/launch-claude-session.sh &
  sleep 0.5
  hyprctl dispatch togglespecialworkspace claude
fi
