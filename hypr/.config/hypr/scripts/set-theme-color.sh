#!/usr/bin/env bash
# Manually pin the accent color (used by Hyprland borders, Waybar, rofi,
# swaync, wlogout, and eww — all driven off matugen's generated palette)
# instead of letting it be derived from the wallpaper.
#
# Usage:
#   set-theme-color.sh '#ff6a00'   set a specific accent color
#   set-theme-color.sh wallpaper   go back to wallpaper-derived colors
set -euo pipefail

CONFIG_DIR="${HOME}/.config/hyprland-rice"
OVERRIDE_FILE="${CONFIG_DIR}/theme.conf"

usage() {
  echo "Usage: $(basename "$0") '#rrggbb' | wallpaper" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

mkdir -p "${CONFIG_DIR}"

if [[ "$1" == "wallpaper" ]]; then
  rm -f "${OVERRIDE_FILE}"
  matugen image ~/.config/hypr/wallpaper.png -m dark --prefer=saturation
  notify-send "Theme" "Reverted to wallpaper-derived accent color" 2>/dev/null || true
  exit 0
fi

COLOR="$1"
if [[ ! "${COLOR}" =~ ^#[0-9a-fA-F]{6}$ ]]; then
  echo "Error: '${COLOR}' is not a hex color like #ff6a00" >&2
  exit 1
fi

cat > "${OVERRIDE_FILE}" <<EOF
ACCENT_SOURCE=color
ACCENT_COLOR=${COLOR}
EOF

matugen color hex "${COLOR}" -m dark
notify-send "Theme" "Accent color set to ${COLOR}" 2>/dev/null || true
