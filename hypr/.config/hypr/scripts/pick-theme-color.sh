#!/usr/bin/env bash
# Rofi front-end for set-theme-color.sh: offers a handful of presets plus a
# free-form hex entry, and a way back to the wallpaper-derived scheme.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRESETS=(
  "Wallpaper (auto)|wallpaper"
  "Orange|#ff6a00"
  "Red|#e53935"
  "Pink|#e91e8c"
  "Purple|#8e24aa"
  "Blue|#1e88e5"
  "Teal|#00897b"
  "Green|#43a047"
  "Custom hex…|custom"
)

CHOICE="$(printf '%s\n' "${PRESETS[@]}" | cut -d'|' -f1 \
  | rofi -dmenu -p "Accent color" -i)"

[[ -n "${CHOICE}" ]] || exit 0

VALUE=""
for entry in "${PRESETS[@]}"; do
  if [[ "${entry%%|*}" == "${CHOICE}" ]]; then
    VALUE="${entry#*|}"
    break
  fi
done

if [[ "${VALUE}" == "custom" ]]; then
  VALUE="$(rofi -dmenu -p "Hex color (e.g. #ff6a00)")"
  [[ -n "${VALUE}" ]] || exit 0
fi

[[ -n "${VALUE}" ]] || exit 0

"${SCRIPT_DIR}/set-theme-color.sh" "${VALUE}"
