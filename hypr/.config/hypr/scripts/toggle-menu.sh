#!/usr/bin/env bash
# toggle-menu.sh <eww-window-name> — shared open/close wrapper for every
# "hypr-menu"-style eww popup (power-menu, volume-popup, proxmox-dashboard,
# and any future one). Bind menu triggers (Hyprland binds, waybar on-click)
# to this instead of calling `eww open --toggle` directly, so the
# Escape-to-close submap (menu-style.conf) is entered/exited correctly.
#
# Checks eww's own active-window list first rather than blindly entering
# the submap on every call — otherwise pressing the same trigger a second
# time to CLOSE the menu would re-enter the submap right as the menu
# closes, leaving Escape/other keys stuck until the next outside click.
set -euo pipefail

name="${1:?usage: toggle-menu.sh <eww-window-name>}"

if eww active-windows | grep -q "^${name}:"; then
  ~/.config/hypr/scripts/close-all-menus.sh
else
  hyprctl dispatch submap menu >/dev/null
  eww open "${name}"
fi
