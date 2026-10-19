#!/bin/bash
# Generates the Xcode project and runs the unit tests.
# Usage: scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen manquant. Installe-le avec : brew install xcodegen" >&2
  exit 1
fi

# ffmpeg is embedded in the app and used by the tests (§3).
if [ ! -x Vendor/ffmpeg/ffmpeg ] || [ ! -x Vendor/ffmpeg/ffprobe ]; then
  scripts/fetch-ffmpeg.sh
fi

xcodegen generate --quiet
mkdir -p build
LOG=build/xcodebuild-test.log
if ! xcodebuild -project Pivot.xcodeproj -scheme Pivot \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' test >"$LOG" 2>&1; then
  grep -E 'error:|failed' "$LOG" | sort -u >&2
  echo "TESTS FAILED (log complet : $LOG)" >&2
  exit 1
fi
grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
echo "TESTS OK"
