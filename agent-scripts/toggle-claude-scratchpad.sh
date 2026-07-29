#!/usr/bin/env bash
# Toggles a Hyprland special workspace running Claude Code in a terminal.
# Bound to SUPER+grave in hyprland.conf. Spawns the terminal on first use,
# just toggles visibility after that (see windowrulev2 in hyprland.conf for
# how the "claude-scratchpad" class window gets pinned to this workspace).
set -euo pipefail

CLASS="claude-scratchpad"

if hyprctl clients -j | jq -e --arg c "$CLASS" '[.[] | select(.class == $c)] | length > 0' >/dev/null; then
  hyprctl dispatch togglespecialworkspace claude
else
  kitty --class "$CLASS" -e claude &
  sleep 0.5
  hyprctl dispatch togglespecialworkspace claude
fi
