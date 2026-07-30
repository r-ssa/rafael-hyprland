#!/usr/bin/env bash
# "Idle settings" tile in wlogout (SUPER+Q): edit hypridle.conf's timeouts
# (lock, screen-off, suspend) from a rofi menu instead of hand-editing the
# file. Each listener block in hypridle.conf is identified by its
# on-timeout command, not position, so this survives reordering the file.
set -euo pipefail

CONF="${HOME}/.config/hypr/hypridle.conf"

get_timeout() {
  # Anchored to line-start so this doesn't also match "on-timeout = " lines
  # (which contain "timeout = " as a substring and would otherwise clobber
  # the value just read before it's printed).
  awk -v pat="$1" '
    /listener {/ { in_block=1; timeout="" }
    in_block && /^[ \t]*timeout = / { match($0, /[0-9]+/); timeout = substr($0, RSTART, RLENGTH) }
    in_block && /on-timeout = / && $0 ~ pat { print timeout; exit }
    /}/ { in_block = 0 }
  ' "${CONF}"
}

fmt_min() { echo "$(( $1 / 60 ))m"; }

LOCK_S="$(get_timeout "lock-session")"
DPMS_S="$(get_timeout "dpms off")"
SUSPEND_S="$(get_timeout "systemctl suspend")"

CHOICE="$(printf "Lock screen — currently %s\nTurn off screen — currently %s\nSuspend — currently %s\n" \
  "$(fmt_min "${LOCK_S}")" "$(fmt_min "${DPMS_S}")" "$(fmt_min "${SUSPEND_S}")" \
  | rofi -dmenu -p "Idle settings" -i -theme-str 'window {width: 500px;}')"

[[ -n "${CHOICE}" ]] || exit 0

case "${CHOICE}" in
  Lock*) PAT="lock-session"; LABEL="Lock screen" ;;
  Turn*) PAT="dpms off"; LABEL="Turn off screen" ;;
  Suspend*) PAT="systemctl suspend"; LABEL="Suspend" ;;
  *) exit 0 ;;
esac

NEW_MIN="$(rofi -dmenu -p "${LABEL} after how many minutes?" -theme-str 'window {width: 500px;}')"
[[ "${NEW_MIN}" =~ ^[0-9]+$ ]] || { notify-send "Idle settings" "Not a whole number of minutes — nothing changed."; exit 1; }
NEW_S=$(( NEW_MIN * 60 ))

awk -v pat="${PAT}" -v new="${NEW_S}" '
  /listener {/ { in_block = 1; buf = "" }
  in_block { buf = buf $0 "\n" }
  in_block && /on-timeout = / && $0 ~ pat { gsub(/timeout = [0-9]+/, "timeout = " new, buf) }
  /}/ && in_block { printf "%s", buf; in_block = 0; next }
  !in_block { print }
' "${CONF}" > "${CONF}.tmp"
mv "${CONF}.tmp" "${CONF}"

pkill hypridle 2>/dev/null || true
hyprctl dispatch exec hypridle

notify-send "Idle settings" "${LABEL} now after ${NEW_MIN}m"
