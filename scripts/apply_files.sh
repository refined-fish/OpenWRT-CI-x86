#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"

FILES_URL="${FILES_ZIP_URL_INPUT:-}"
if [ -z "$FILES_URL" ]; then
  FILES_URL="${FILES_ZIP_URL_SECRET:-}"
fi

if [ -z "$FILES_URL" ]; then
  echo "No files.zip URL provided; skip custom files"
  exit 0
fi

TMP_ZIP="$(mktemp)"
echo "Downloading files.zip"
curl -fL --retry 3 --connect-timeout 20 "$FILES_URL" -o "$TMP_ZIP"

mkdir -p "$OPENWRT_DIR/files"
unzip -o "$TMP_ZIP" -d "$OPENWRT_DIR"
rm -f "$TMP_ZIP"

echo "Custom files applied"
