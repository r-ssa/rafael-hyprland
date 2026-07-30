#!/usr/bin/env bash
# JSON for the eww volume-popup slider: current level + mute state of the
# default sink, plus its human-readable description for the label.
set -euo pipefail

vol="$(pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}' | head -1 | tr -d '%')"
muted="$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')"
desc="$(pactl get-sink-volume @DEFAULT_SINK@ >/dev/null; pactl -f json list sinks \
  | jq -r --arg name "$(pactl get-default-sink)" '.[] | select(.name == $name) | .description')"

jq -n --arg vol "$vol" --arg muted "$muted" --arg desc "$desc" \
  '{volume: ($vol | tonumber), muted: ($muted == "yes"), desc: $desc}'
