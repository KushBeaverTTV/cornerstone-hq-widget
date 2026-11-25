#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(bash "$DIR/hq-state.sh")"

echo "$OUT" | jq -e '
  (.windows | type == "number") and
  (.services | type == "array") and
  (.services | length == 6) and
  (.services | map(.unit) | index("yt-cipher") != null)
' >/dev/null

echo "PASS cornerstone.hq state tests"
