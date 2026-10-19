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

xcodegen generate --quiet
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration "$CONFIG" \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' build \
  | grep -E '(error|warning:|BUILD )' || true
test -d "build/Build/Products/$CONFIG/Pivot.app" && echo "→ build/Build/Products/$CONFIG/Pivot.app"
