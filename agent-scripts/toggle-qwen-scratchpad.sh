#!/usr/bin/env bash
# Toggles a Hyprland special workspace running a Claude-Code-styled chat UI
# for qwen2.5:3b (via Ollama on the ollama-host VM, see
# ~/scripts (on the VM)/qwen_chat.py — a rich/prompt_toolkit TUI, blue theme).
# Bound to SUPER+F2 in hyprland.conf — mirrors toggle-claude-scratchpad.sh
# (SUPER+F1) exactly, just a different model. Spawns the terminal on first
# use, just toggles visibility after that (see windowrule in hyprland.conf
# for how the "qwen-scratchpad" class window gets pinned to this workspace).
set -euo pipefail

CLASS="qwen-scratchpad"
VM_HOST="rafael@192.168.1.97"

if hyprctl clients -j | jq -e --arg c "$CLASS" '[.[] | select(.class == $c)] | length > 0' >/dev/null; then
  hyprctl dispatch togglespecialworkspace qwen
else
  kitty --class "$CLASS" -o initial_window_width=1100 -o initial_window_height=750 \
    -e ssh -t "$VM_HOST" "python3 /home/rafael/scripts/qwen_chat.py" &
  sleep 0.5
  hyprctl dispatch togglespecialworkspace qwen
fi
