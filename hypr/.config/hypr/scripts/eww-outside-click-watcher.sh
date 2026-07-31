#!/usr/bin/env bash
# Closes power-menu/volume-popup/proxmox-dashboard the moment focus moves
# to any other window — the "click anywhere outside to dismiss" behavior,
# implemented at the Hyprland level instead of a GTK trick. A full-monitor
# invisible eww window was tried first to catch outside clicks directly,
# but its background never actually composited as transparent and
# blacked out the whole screen instead — this avoids that class of bug
# entirely by not touching the popup's own surface at all.
#
# Hyprland emits `activewindow>>class,title` on its event socket every
# time window focus changes. Any such event means the user clicked (or
# otherwise focused) something that isn't one of our layer-shell popups
# — those aren't regular windows and don't participate in activewindow —
# so on every event we just close whichever of the three happen to be
# open (close-all-menus.sh, shared with the Escape-to-close submap in
# menu-style.conf — it also resets that submap). Redundant closes are
# harmless, so no need to track which one is open.
set -euo pipefail

SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

socat -U - "UNIX-CONNECT:${SOCK}" | while read -r line; do
  case "${line}" in
    activewindow\>\>*)
      ~/.config/hypr/scripts/close-all-menus.sh
      ;;
  esac
done
