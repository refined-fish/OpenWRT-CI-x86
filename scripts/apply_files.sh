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
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -f "$TMP_ZIP"
  if [ -d "$TMP_DIR" ]; then
    chmod -R u+rwX "$TMP_DIR" 2>/dev/null || true
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

echo "Downloading files.zip"
curl -fL --retry 3 --connect-timeout 20 "$FILES_URL" -o "$TMP_ZIP"
unzip -tq "$TMP_ZIP"
unzip -oq "$TMP_ZIP" -d "$TMP_DIR"
chmod -R u+rwX "$TMP_DIR" 2>/dev/null || true

mkdir -p "$OPENWRT_DIR/files"
if [ -d "$TMP_DIR/files" ]; then
  echo "Detected files/ directory in archive"
  cp -a "$TMP_DIR/files/." "$OPENWRT_DIR/files/"
else
  echo "Archive does not contain top-level files/ directory; treating archive root as files/ content"
  cp -a "$TMP_DIR/." "$OPENWRT_DIR/files/"
fi
chmod -R u+rwX "$OPENWRT_DIR/files" 2>/dev/null || true

echo "Custom files applied to $OPENWRT_DIR/files"
