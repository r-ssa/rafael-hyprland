#!/usr/bin/env bash
# Generic boolean flip for an eww `defvar` — used by the power menu's
# Logout row (right-click toggles logout_expanded to reveal Lock/Relogin)
# instead of writing a one-off toggler per variable.
set -euo pipefail

VAR="${1:?Usage: toggle-eww-var.sh <var-name>}"

CURRENT="$(eww get "${VAR}")"
if [[ "${CURRENT}" == "true" ]]; then
  eww update "${VAR}=false"
else
  eww update "${VAR}=true"
fi
