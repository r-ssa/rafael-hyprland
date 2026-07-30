#!/usr/bin/env bash
# Runs on every Hyprland login (exec-once) to (re)generate matugen colors.
# If the user has picked a manual accent color via set-theme-color.sh, that
# takes priority over the wallpaper-derived scheme, so a manual choice
# survives reboots instead of being clobbered by the wallpaper every login.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDE_FILE="${HOME}/.config/hyprland-rice/theme.conf"

if [[ -f "${OVERRIDE_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${OVERRIDE_FILE}"
fi

if [[ "${ACCENT_SOURCE:-wallpaper}" == "color" && -n "${ACCENT_COLOR:-}" ]]; then
  # Delegate to set-theme-color.sh instead of calling matugen directly —
  # it also handles the grayscale (white/black) literal-color override,
  # which plain matugen gets wrong (see its comments). Duplicating that
  # logic here previously meant a pinned white/black accent reverted to
  # the wrong color on every login.
  THEME_INIT_QUIET=1 "${SCRIPT_DIR}/set-theme-color.sh" "${ACCENT_COLOR}"
else
  matugen image ~/.config/hypr/wallpaper.png -m dark --prefer=saturation
fi
