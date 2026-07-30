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

# Material You's HCT color space derives everything from hue, which is
# undefined for grayscale input — feeding it pure white/black produces an
# arbitrary unrelated hue (verified: #ffffff -> a cyan primary, #000000 ->
# a pink primary), not white/black. For grayscale colors, skip the Material
# derivation for just the accent role and force it literally instead.
hex="${COLOR#\#}"
r="${hex:0:2}"; g="${hex:2:2}"; b="${hex:4:2}"
if [[ "${r}" == "${g}" && "${g}" == "${b}" ]]; then
  # Perceptual luminance (ITU-R BT.601) decides whether accent text needs
  # to be black or white to stay readable on top of it.
  ri=$((16#${r})); gi=$((16#${g})); bi=$((16#${b}))
  lum=$(( (299 * ri + 587 * gi + 114 * bi) / 1000 ))
  if (( lum > 140 )); then on_hex="000000"; else on_hex="ffffff"; fi

  sed -i -E "s/^\\\$accent = rgb\([0-9a-fA-F]{6}\)/\$accent = rgb(${hex})/" \
    "${HOME}/.config/hypr/colors.conf"
  sed -i -E "s/^\\\$on_accent = rgb\([0-9a-fA-F]{6}\)/\$on_accent = rgb(${on_hex})/" \
    "${HOME}/.config/hypr/colors.conf"

  sed -i -E "s/@define-color accent #[0-9a-fA-F]{6};/@define-color accent #${hex};/;
             s/@define-color on_accent #[0-9a-fA-F]{6};/@define-color on_accent #${on_hex};/" \
    "${HOME}/.config/waybar/colors.css"

  for f in "${HOME}/.config/swaync/colors.css" "${HOME}/.config/wlogout/colors.css" \
           "${HOME}/.config/eww/colors.css"; do
    [[ -f "${f}" ]] && sed -i -E "s/@define-color accent #[0-9a-fA-F]{6};/@define-color accent #${hex};/" "${f}"
  done

  sed -i -E "s/accent: #[0-9a-fA-F]{6};/accent: #${hex};/" "${HOME}/.config/rofi/colors.rasi"

  if [[ -f "${HOME}/.config/kitty/colors.conf" ]]; then
    sed -i -E "s/^selection_background #[0-9a-fA-F]{6}/selection_background #${hex}/;
               s/^selection_foreground #[0-9a-fA-F]{6}/selection_foreground #${on_hex}/;
               s/^cursor #[0-9a-fA-F]{6}/cursor #${hex}/;
               s/^url_color #[0-9a-fA-F]{6}/url_color #${hex}/" \
      "${HOME}/.config/kitty/colors.conf"
    # New kitty windows pick this up immediately; already-open ones need
    # kitty's default ctrl+shift+F5 (reload_config_file) to pick it up —
    # not auto-reloading here since that needs allow_remote_control on.
  fi
fi

[[ -n "${THEME_INIT_QUIET:-}" ]] || notify-send "Theme" "Accent color set to ${COLOR}" 2>/dev/null || true
