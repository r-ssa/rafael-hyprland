#!/usr/bin/env bash
# Shows all Hyprland keybinds via rofi, parsed live from hyprland.conf so
# this can never drift out of sync with the actual config.
set -euo pipefail

CONF="${HOME}/.config/hypr/hyprland.conf"
MAINMOD="$(grep -oP '^\$mainMod\s*=\s*\K\S+' "${CONF}")"

grep -E '^\s*bind[m]?\s*=' "${CONF}" \
  | sed -E "s/^\s*bind[m]?\s*=\s*//; s/\\\$mainMod/${MAINMOD}/g" \
  | awk -F',' '{
      mod = $1; gsub(/^ +| +$/, "", mod)
      key = $2; gsub(/^ +| +$/, "", key)
      disp = $3; gsub(/^ +| +$/, "", disp)
      args = ""
      for (i = 4; i <= NF; i++) { args = args (i > 4 ? "," : "") $i }
      gsub(/^ +| +$/, "", args)
      combo = (mod == "" ? key : mod "+" key)
      printf "%-24s %s %s\n", combo, disp, args
    }' \
  | rofi -dmenu -p "Keybinds" -i -theme-str 'window {width: 700px;} listview {lines: 15;}'
