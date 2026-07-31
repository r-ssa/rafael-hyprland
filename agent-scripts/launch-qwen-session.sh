#!/usr/bin/env bash
# Runs inside the Qwen scratchpad on every fresh spawn: ask which machine
# tool calls should operate on (see pick-target.sh, falls back to local on
# cancel), tunnel Ollama's port from ollama-host (that's where the RX 580
# lives — inference always happens there regardless of the chosen target),
# then launch the local chat UI.
set -uo pipefail

TARGET="$("${HOME}/agent-scripts/pick-target.sh")"
if [[ -z "${TARGET}" ]]; then
  TARGET="local"
fi

# -N: no remote command, just forward. -f would background before the
# tunnel is confirmed up, so instead start it backgrounded via & and give
# it a moment — simpler than parsing -f's early-exit timing.
ssh -o BatchMode=yes -N -L 11434:localhost:11434 rafael@192.168.1.97 &
TUNNEL_PID=$!
trap 'kill "${TUNNEL_PID}" 2>/dev/null' EXIT

for i in $(seq 1 20); do
  if curl -s -o /dev/null -m 1 http://localhost:11434/api/tags; then
    break
  fi
  sleep 0.3
done

QWEN_TARGET_HOST="${TARGET}" python3 "${HOME}/scripts/qwen_chat.py"
