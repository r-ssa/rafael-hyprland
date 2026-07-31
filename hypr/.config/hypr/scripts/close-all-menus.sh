#!/usr/bin/env bash
# close-all-menus.sh — close every eww popup menu and drop out of the
# Hyprland "menu" submap (see menu-style.conf), regardless of which one is
# actually open. Called from three places: the Escape bind inside the
# "menu" submap, eww-outside-click-watcher.sh on any outside click, and
# each popup's own action buttons (eww.yuck) before running their action.
#
# Safe to call even when nothing is open — `eww close` on an already-closed
# window and `submap reset` when not in a submap are both harmless no-ops.
# To add a new menu: add its eww window name to POPUPS below.
set -euo pipefail

POPUPS=(power-menu volume-popup proxmox-dashboard)

for w in "${POPUPS[@]}"; do
  eww close "${w}" >/dev/null 2>&1 || true
done
eww update logout_expanded=false >/dev/null 2>&1 || true
hyprctl dispatch submap reset >/dev/null 2>&1 || true
