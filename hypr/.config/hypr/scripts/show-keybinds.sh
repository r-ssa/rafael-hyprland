#!/usr/bin/env bash
# Shows all Hyprland keybinds via rofi, parsed live from hyprland.conf so
# this can never drift out of sync with the actual config. Each bind line
# carries a trailing "# Description" comment — that's what gets shown,
# not the raw dispatcher/script name, so the list reads as "what this key
# does" instead of "which script this key happens to call". Falls back to
# the raw dispatcher+args for any bind missing a comment.
set -euo pipefail

CONF="${HOME}/.config/hypr/hyprland.conf"
MAINMOD="$(grep -oP '^\$mainMod\s*=\s*\K\S+' "${CONF}")"

grep -E '^\s*bind[m]?\s*=' "${CONF}" \
  | sed -E "s/^\s*bind[m]?\s*=\s*//; s/\\\$mainMod/${MAINMOD}/g" \
  | awk -F'#' '{
      left = $1
      desc = ""
      for (i = 2; i <= NF; i++) { desc = desc (i > 2 ? "#" : "") $i }
      gsub(/^ +| +$/, "", desc)
      gsub(/ +$/, "", left)
      n = split(left, parts, ",")
      mod = parts[1]; gsub(/^ +| +$/, "", mod)
      key = parts[2]; gsub(/^ +| +$/, "", key)
      combo = (mod == "" ? key : mod "+" key)
      if (desc == "") {
        disp = parts[3]; gsub(/^ +| +$/, "", disp)
        args = ""
        for (i = 4; i <= n; i++) { args = args (i > 4 ? "," : "") parts[i] }
        gsub(/^ +| +$/, "", args)
        desc = (args == "" ? disp : disp " " args)
      }
      printf "%-24s %s\n", combo, desc
    }' \
  | rofi -dmenu -p "Keybinds" -i -theme-str 'window {width: 700px;} listview {lines: 15;}'
