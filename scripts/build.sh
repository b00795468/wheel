#!/bin/bash
# Generates the Xcode project and builds Pivot.app.
# Usage: scripts/build.sh [Debug|Release]   → build/Build/Products/<config>/Pivot.app
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"

if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen manquant. Installe-le avec : brew install xcodegen" >&2
  exit 1
fi

source scripts/signing.sh

# ffmpeg is embedded in the app and used by the tests (§3).
if [ ! -x Vendor/ffmpeg/ffmpeg ] || [ ! -x Vendor/ffmpeg/ffprobe ]; then
  scripts/fetch-ffmpeg.sh
fi

xcodegen generate --quiet
mkdir -p build
LOG=build/xcodebuild.log
if ! xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration "$CONFIG" \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build >"$LOG" 2>&1; then
  grep -E 'error:' "$LOG" | sort -u >&2
  echo "BUILD FAILED (log complet : $LOG)" >&2
  exit 1
fi
grep -E 'warning:' "$LOG" | sort -u || true
echo "BUILD OK → build/Build/Products/$CONFIG/Pivot.app ($(codesign -dv --verbose=2 "build/Build/Products/$CONFIG/Pivot.app" 2>&1 | grep -E '^(Authority=|Signature=adhoc)' | head -1))"
