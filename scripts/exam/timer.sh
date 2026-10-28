#!/bin/bash
# Prints the remaining exam time (used by the tmux status bar and the viewer).
STATE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.exam-runtime/state}"
[[ -f "$STATE" ]] || { echo "no exam"; exit 0; }
# shellcheck disable=SC1090
source "$STATE"
remaining=$(( END_TS - $(date +%s) ))
if (( remaining <= 0 )); then
  echo "TIME UP"
else
  printf "%d:%02d:%02d left\n" $((remaining / 3600)) $((remaining % 3600 / 60)) $((remaining % 60))
fi
