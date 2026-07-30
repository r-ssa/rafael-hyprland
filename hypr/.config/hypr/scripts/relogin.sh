#!/usr/bin/env bash
# The power menu's "Relogin" button (see eww/.config/eww/eww.yuck). There's
# no display manager on this machine
# (Hyprland is launched directly from a TTY, see bootstrap.sh's seatd
# setup) so a plain logout just drops back to a bare shell prompt. This
# detaches a delayed Hyprland relaunch — so it survives this compositor
# instance exiting — then exits the current session, giving a quick full
# session cycle for testing config changes without retyping `Hyprland`.
set -euo pipefail

setsid bash -c 'sleep 1; exec Hyprland' >"${HOME}/.cache/hypr-relogin.log" 2>&1 &
disown

hyprctl dispatch exit
