#!/usr/bin/env bash
#
# Runs every package's tests with coverage, holds each to the same floor, and
# checks that no exported name goes unmentioned by a test.
#
#   bash tool/coverage.sh [min-percent]
set -euo pipefail

MIN="${1:-99.5}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

for pkg in engine mcp cli; do
  cd "$ROOT/packages/$pkg"
  rm -rf coverage
  dart test --coverage=coverage >/dev/null
  dart pub global run coverage:format_coverage \
    --lcov --in=coverage --out=coverage/lcov.info \
    --report-on=lib --packages="$ROOT/.dart_tool/package_config.json" >/dev/null
  printf '%-8s' "$pkg"
  bash "$ROOT/tool/check_coverage.sh" coverage/lcov.info "$MIN" || status=1
done

cd "$ROOT/app"
flutter test --coverage >/dev/null
printf '%-8s' app
bash "$ROOT/tool/check_coverage.sh" coverage/lcov.info "$MIN" || status=1

echo
python3 "$ROOT/tool/api_coverage.py" "$MIN" || status=1
exit "$status"
