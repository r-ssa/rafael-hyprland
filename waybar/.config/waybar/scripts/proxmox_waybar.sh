#!/usr/bin/env bash
# Reformats proxmox_stats.py's JSON into what Waybar's custom module expects
# ({"text", "tooltip", "class"}). Kept separate from proxmox_stats.py so the
# eww dashboard can consume the same raw stats without Waybar-specific shaping.
set -euo pipefail

RAW="$(~/.local/bin/proxmox_stats.py)"
STATUS="$(jq -r '.status' <<< "$RAW")"

case "$STATUS" in
  ok)
    CPU="$(jq -r '.node.cpu_pct' <<< "$RAW")"
    MEM="$(jq -r '.node.mem_pct' <<< "$RAW")"
    RUNNING="$(jq -r '[.guests[] | select(.status == "running")] | length' <<< "$RAW")"
    TOTAL="$(jq -r '.guests | length' <<< "$RAW")"
    jq -nc --arg text "PVE ${CPU}% / ${MEM}% (${RUNNING}/${TOTAL})" \
          --arg tooltip "Node CPU ${CPU}%, mem ${MEM}% — ${RUNNING}/${TOTAL} guests running" \
          '{text: $text, tooltip: $tooltip, class: "ok"}'
    ;;
  network_down)
    jq -nc '{text: "PVE: your network is down", tooltip: "Could not reach the local gateway", class: "error"}'
    ;;
  timeout)
    jq -nc '{text: "PVE: slow/timeout", tooltip: "Proxmox host is not responding in time", class: "warn"}'
    ;;
  unreachable)
    MSG="$(jq -r '.message' <<< "$RAW")"
    jq -nc --arg tooltip "$MSG" '{text: "PVE: unreachable", tooltip: $tooltip, class: "error"}'
    ;;
  auth_error)
    jq -nc '{text: "PVE: auth error", tooltip: "API token was rejected — check proxmox.conf", class: "error"}'
    ;;
  config_error)
    jq -nc '{text: "PVE: not configured", tooltip: "Run bootstrap.sh to set up proxmox.conf", class: "disabled"}'
    ;;
  *)
    jq -nc '{text: "PVE: error", tooltip: "Unexpected error polling Proxmox", class: "error"}'
    ;;
esac
