#!/usr/bin/env bash
#
# Builds the desktop app and launches it, refusing to open a bundle whose code
# is older than the build that just ran.
#
# Renaming the product once left Xcode copying nothing into the bundle while
# still exiting 0, so two builds in a row launched hours-old code. Checking the
# embedded framework is cheap and catches it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app/build/macos/Build/Products/Release/AI Tracker.app"
EMBEDDED="$APP/Contents/Frameworks/App.framework/App"

cd "$ROOT/app"
started="$(date +%s)"
flutter build macos --release

if [ ! -f "$EMBEDDED" ]; then
  echo "no code inside the bundle at $EMBEDDED" >&2
  exit 1
fi

written="$(stat -f %m "$EMBEDDED")"
if [ "$written" -lt "$started" ]; then
  echo "the bundle holds code older than this build; cleaning and trying once more" >&2
  flutter clean >/dev/null
  flutter build macos --release
  written="$(stat -f %m "$EMBEDDED")"
  if [ "$written" -lt "$started" ]; then
    echo "still stale after a clean build: $EMBEDDED" >&2
    exit 1
  fi
fi

osascript -e 'quit app "AI Tracker"' 2>/dev/null || true
sleep 1
open "$APP"
echo "launched $APP"
