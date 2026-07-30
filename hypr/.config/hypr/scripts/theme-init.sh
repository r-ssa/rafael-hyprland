#!/usr/bin/env bash
# Runs on every Hyprland login (exec-once) to (re)generate matugen colors.
# If the user has picked a manual accent color via set-theme-color.sh, that
# takes priority over the wallpaper-derived scheme, so a manual choice
# survives reboots instead of being clobbered by the wallpaper every login.
set -euo pipefail

OVERRIDE_FILE="${HOME}/.config/hyprland-rice/theme.conf"

if [[ -f "${OVERRIDE_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${OVERRIDE_FILE}"
fi

if [[ "${ACCENT_SOURCE:-wallpaper}" == "color" && -n "${ACCENT_COLOR:-}" ]]; then
  matugen color hex "${ACCENT_COLOR}" -m dark
else
  matugen image ~/.config/hypr/wallpaper.png -m dark --prefer=saturation
fi
