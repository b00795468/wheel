#!/bin/bash
# Downloads the static arm64 ffmpeg/ffprobe build validated for Pivot (§3)
# into Vendor/ffmpeg/, checking pinned SHA-256 sums. Not versioned (size).
# Usage: scripts/fetch-ffmpeg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="9.0.2"
BASE_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_${VERSION}"
DEST="Vendor/ffmpeg"
# SHA-256 of the zips, as published next to them (checked on 2026-10-19).
SHA_ffmpeg="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
SHA_ffprobe="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"

mkdir -p "$DEST"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for tool in ffmpeg ffprobe; do
  if [ -x "$DEST/$tool" ] && [ "$(cat "$DEST/$tool.version" 2>/dev/null)" = "$VERSION" ]; then
    echo "${tool} ${VERSION} déjà présent"
    continue
  fi
  echo "Téléchargement de ${tool} ${VERSION}…"
  curl -fsSL -o "$TMP/$tool.zip" "$BASE_URL/$tool.zip"
  expected_var="SHA_$tool"
  actual=$(shasum -a 256 "$TMP/$tool.zip" | cut -d' ' -f1)
  if [ "$actual" != "${!expected_var}" ]; then
    echo "SHA-256 inattendu pour ${tool}.zip : ${actual}" >&2
    exit 1
  fi
  ditto -x -k "$TMP/$tool.zip" "$TMP/$tool"
  ditto "$TMP/$tool/$tool" "$DEST/$tool"
  echo "$VERSION" > "$DEST/$tool.version"
done

# Only system libraries are allowed (§3): no Homebrew or /usr/local paths.
if otool -L "$DEST/ffmpeg" "$DEST/ffprobe" | grep -E '/opt/|/usr/local/'; then
  echo "Dépendance non système détectée" >&2
  exit 1
fi
echo "ffmpeg ${VERSION} prêt dans ${DEST}"
