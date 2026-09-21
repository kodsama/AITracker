#!/usr/bin/env bash
#
# Builds the EventKit helper that publishes the AI hours as a calendar, and puts
# it where the engine looks for it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$HOME/.local/bin}"

mkdir -p "$OUT"
swiftc -O -framework EventKit \
  -o "$OUT/aitracker-calendar" \
  "$ROOT/tool/aitracker-calendar.swift"
echo "built $OUT/aitracker-calendar"
