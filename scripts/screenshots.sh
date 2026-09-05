#!/bin/bash
# Cutaway — regenerate the README screenshots into docs/assets.
# Usage: scripts/screenshots.sh
# Drives the real app through the UI-test target (ScreenshotCaptureTests):
# demo data, quarantined store, element screenshots at screen scale.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
CUTAWAY_CAPTURE=1 TEST_RUNNER_CUTAWAY_CAPTURE=1 \
xcodebuild -project "$ROOT/Cutaway.xcodeproj" -scheme Cutaway -destination 'platform=macOS' \
  test -only-testing:CutawayUITests/ScreenshotCaptureTests > "$LOG" 2>&1 || true
grep -E "Test Case|error:|TEST (FAILED|SUCCEEDED)" "$LOG" | grep -v linkd
OUT="$(grep -o 'CUTAWAY_CAPTURE_DIR=.*' "$LOG" | head -1 | cut -d= -f2-)"
[ -n "$OUT" ] && [ -d "$OUT" ] || { echo "no capture dir in the log"; exit 1; }
for f in stats panel pill; do
  [ -f "$OUT/$f.png" ] || { echo "missing $f.png"; exit 1; }
  cp "$OUT/$f.png" "$ROOT/docs/assets/$f.png"
  echo "docs/assets/$f.png: $(sips -g pixelWidth -g pixelHeight "$ROOT/docs/assets/$f.png" | awk '/pixel/{print $2}' | paste -sd x -)"
done
rm -f "$LOG"
