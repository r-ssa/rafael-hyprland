#!/usr/bin/env bash
# Rofi front-end for output/input device switching, bound to right-click on
# waybar's pulseaudio module. Volume level/mute live in the eww slider
# popup (volume-popup, left-click) — this is purely a device selector.
set -euo pipefail

DEFAULT_SINK_NAME="$(pactl get-default-sink)"
DEFAULT_SOURCE_NAME="$(pactl get-default-source)"

OPTIONS=()

while IFS='|' read -r sink_name sink_desc; do
  [[ -z "${sink_name}" ]] && continue
  mark=" "
  [[ "${sink_name}" == "${DEFAULT_SINK_NAME}" ]] && mark="✓"
  OPTIONS+=("[${mark}] Output: ${sink_desc}|switch_sink:${sink_name}")
done < <(pactl -f json list sinks | jq -r '.[] | "\(.name)|\(.description)"')

OPTIONS+=("──────────|noop")

while IFS='|' read -r source_name source_desc; do
  [[ -z "${source_name}" ]] && continue
  # Skip monitor sources (every sink has a paired ".monitor" source for
  # loopback/recording-what-you-hear — not a real input device to pick).
  [[ "${source_name}" == *.monitor ]] && continue
  mark=" "
  [[ "${source_name}" == "${DEFAULT_SOURCE_NAME}" ]] && mark="✓"
  OPTIONS+=("[${mark}] Input: ${source_desc}|switch_source:${source_name}")
done < <(pactl -f json list sources | jq -r '.[] | "\(.name)|\(.description)"')

OPTIONS+=("──────────|noop")
OPTIONS+=("Open full mixer (pavucontrol)|mixer")

CHOICE="$(printf '%s\n' "${OPTIONS[@]}" | cut -d'|' -f1 \
  | rofi -dmenu -p "Audio devices" -i)"

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
  mixer) pavucontrol & disown ;;
  switch_sink:*) pactl set-default-sink "${ACTION#switch_sink:}" ;;
  switch_source:*) pactl set-default-source "${ACTION#switch_source:}" ;;
esac
