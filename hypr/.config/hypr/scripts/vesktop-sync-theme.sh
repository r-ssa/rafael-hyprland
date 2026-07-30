#!/usr/bin/env bash
# Ensures Vesktop's native "transparent" window setting stays on (needed
# for any transparency theme to have anything to show through). Chrome
# recoloring is deliberately NOT done here — Discord's internal CSS custom
# properties change across client redesigns often enough that hardcoding
# them here would just go stale; use Vencord's own Themes tab (User
# Settings -> Vencord -> Themes) instead, which actual theme authors keep
# up to date.
set -euo pipefail

SETTINGS="${HOME}/.config/vesktop/settings/settings.json"

[[ -f "${SETTINGS}" ]] || { echo "Vesktop not set up yet, skipping" >&2; exit 0; }

python3 - "${SETTINGS}" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["transparent"] = True
with open(path, "w") as f:
    json.dump(data, f, indent=4)
EOF
