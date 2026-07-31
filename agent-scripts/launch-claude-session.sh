#!/usr/bin/env bash
# Runs inside the Claude Code scratchpad on every fresh spawn: ask which
# machine to work on, then either run claude locally or SSH in and run it
# there. Falls back to local if the picker is cancelled (Esc).
set -uo pipefail

TARGET="$("${HOME}/agent-scripts/pick-target.sh")"
if [[ -z "${TARGET}" || "${TARGET}" == "local" ]]; then
  exec claude
fi

exec ssh -t "${TARGET}" 'cd ~ && exec "$HOME/.local/bin/claude"'
