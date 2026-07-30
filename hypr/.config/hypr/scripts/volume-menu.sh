#!/usr/bin/env bash
# Rofi front-end for audio control: quick volume levels, mute toggle,
# output device switching, and a way out to the full pavucontrol mixer
# for per-app volume. Bound to right-click on waybar's pulseaudio module
# (left-click still toggles mute, scroll still does +/-5%).
set -euo pipefail

get_volume() {
  pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}' | head -1 | tr -d '%'
}

get_mute() {
  pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}'
}

CURRENT_VOL="$(get_volume)"
CURRENT_MUTE="$(get_mute)"
MUTE_LABEL="Mute"
[[ "${CURRENT_MUTE}" == "yes" ]] && MUTE_LABEL="Unmute"

DEFAULT_SINK_NAME="$(pactl get-default-sink)"

OPTIONS=(
  "Volume: ${CURRENT_VOL}% (muted: ${CURRENT_MUTE})|noop"
  "──────────|noop"
  "+5%|vol_up"
  "-5%|vol_down"
  "${MUTE_LABEL}|toggle_mute"
  "Set to 25%|set_25"
  "Set to 50%|set_50"
  "Set to 75%|set_75"
  "Set to 100%|set_100"
)

# Output device switcher: one entry per sink, current one marked.
while IFS='|' read -r sink_name sink_desc; do
  [[ -z "${sink_name}" ]] && continue
  mark=" "
  [[ "${sink_name}" == "${DEFAULT_SINK_NAME}" ]] && mark="✓"
  OPTIONS+=("[${mark}] Output: ${sink_desc}|switch:${sink_name}")
done < <(pactl -f json list sinks | jq -r '.[] | "\(.name)|\(.description)"')

OPTIONS+=("──────────|noop")
OPTIONS+=("Open full mixer (pavucontrol)|mixer")

CHOICE="$(printf '%s\n' "${OPTIONS[@]}" | cut -d'|' -f1 \
  | rofi -dmenu -p "Volume" -i)"

[[ -n "${CHOICE}" ]] || exit 0

ACTION=""
for entry in "${OPTIONS[@]}"; do
  if [[ "${entry%%|*}" == "${CHOICE}" ]]; then
    ACTION="${entry#*|}"
    break
  fi
done

case "${ACTION}" in
  noop|"") exit 0 ;;
  vol_up) pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
  vol_down) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
  toggle_mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
  set_25) pactl set-sink-volume @DEFAULT_SINK@ 25% ;;
  set_50) pactl set-sink-volume @DEFAULT_SINK@ 50% ;;
  set_75) pactl set-sink-volume @DEFAULT_SINK@ 75% ;;
  set_100) pactl set-sink-volume @DEFAULT_SINK@ 100% ;;
  mixer) pavucontrol & disown ;;
  switch:*) pactl set-default-sink "${ACTION#switch:}" ;;
esac
