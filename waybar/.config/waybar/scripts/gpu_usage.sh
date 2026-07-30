#!/usr/bin/env bash
# GPU utilization %, queried from nvidia-smi. Plain number for waybar's
# custom module text interpolation ({} in the format string).
set -euo pipefail

nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits
