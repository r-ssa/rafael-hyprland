#!/usr/bin/env bash
# Toggles a Hyprland special workspace running a Claude-Code-styled agentic
# chat UI for qwen2.5:3b. Runs locally (~/scripts/qwen_chat.py), talks to
# Ollama on ollama-host over an SSH tunnel (the RX 580 lives there), and on
# every fresh spawn asks which machine tool calls (file/bash) should target
# — see launch-qwen-session.sh / pick-target.sh. Bound to SUPER+F2 in
# hyprland.conf — mirrors toggle-claude-scratchpad.sh (SUPER+F1) exactly,
# just a different model. Spawns the terminal on first use, just toggles
# visibility after that (see windowrule in hyprland.conf for how the
# "qwen-scratchpad" class window gets pinned to this workspace).
set -euo pipefail

CLASS="qwen-scratchpad"

if hyprctl clients -j | jq -e --arg c "$CLASS" '[.[] | select(.class == $c)] | length > 0' >/dev/null; then
  hyprctl dispatch togglespecialworkspace qwen
else
  kitty --class "$CLASS" -o initial_window_width=1100 -o initial_window_height=750 \
    -e ~/agent-scripts/launch-qwen-session.sh &
  sleep 0.5
  hyprctl dispatch togglespecialworkspace qwen
fi
