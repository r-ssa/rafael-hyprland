#!/usr/bin/env bash
# Night light quick-toggle in the power menu (see eww/.config/eww/eww.yuck).
# hyprsunset must already be running (exec-once'd in hyprland.conf) — it
# owns a socket that `hyprctl hyprsunset` talks to; there's nothing to
# start here, just tell it to switch between a warm filter and identity
# (no filter). State is tracked in the eww nightlight_active var so the
# quick-icon-btn can highlight itself while active.
set -euo pipefail

WARM_TEMP=4000

if [[ "$(eww get nightlight_active)" == "true" ]]; then
  hyprctl hyprsunset identity
  eww update nightlight_active=false
else
  hyprctl hyprsunset temperature "${WARM_TEMP}"
  eww update nightlight_active=true
fi
