#!/usr/bin/env bash
#
# Runs every package's tests with coverage and holds each to the same floor.
#
#   bash tool/coverage.sh [min-percent]
set -euo pipefail

MIN="${1:-90}"
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
flutter test >/dev/null && echo "app      ✓ widget tests passed"
exit "$status"
