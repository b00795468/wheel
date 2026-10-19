#!/bin/bash
# Builds the deliverables for Raphaël's brother (SPEC §8) into dist/:
# Pivot.app (Release, arm64, ffmpeg embedded and signed), Pivot.zip,
# INSTALLATION.md and INSTALLATION.pdf, then runs the delivery checks.
# Usage: scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
command -v pandoc >/dev/null || { echo "pandoc manquant (sert au PDF du guide)" >&2; exit 1; }
[ -x "$CHROME" ] || { echo "Google Chrome manquant (sert au PDF du guide)" >&2; exit 1; }

scripts/build.sh Release
rm -rf dist
mkdir -p dist
ditto build/Build/Products/Release/Pivot.app dist/Pivot.app
# ditto keeps the signature, extended attributes and the app bundle intact.
(cd dist && ditto -c -k --keepParent Pivot.app Pivot.zip)

cp docs/INSTALLATION.md dist/INSTALLATION.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pandoc docs/INSTALLATION.md -s -o "$TMP/INSTALLATION.html" --metadata title="Installer Pivot" \
  -c "file://$PWD/docs/installation.css"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$PWD/dist/INSTALLATION.pdf" "file://$TMP/INSTALLATION.html" 2>/dev/null

echo "== Signature"
codesign --verify --deep --strict dist/Pivot.app && echo "signature valide"
codesign -dv --verbose=2 dist/Pivot.app 2>&1 | grep -E '^(Identifier|Authority|Signature|TeamIdentifier)='
codesign -dv --verbose=2 dist/Pivot.app/Contents/Resources/bin/ffmpeg 2>&1 | grep -E '^(Authority|Signature)='
echo "== Architecture et dépendances de ffmpeg"
lipo -archs dist/Pivot.app/Contents/MacOS/Pivot
if otool -L dist/Pivot.app/Contents/Resources/bin/ffmpeg dist/Pivot.app/Contents/Resources/bin/ffprobe | grep -E '/opt/|/usr/local/'; then
  echo "Dépendance non système" >&2; exit 1
fi
echo "ffmpeg et ffprobe : bibliothèques système uniquement"
echo "== Livrables"
ls -lh dist
