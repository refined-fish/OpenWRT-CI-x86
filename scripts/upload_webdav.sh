#!/usr/bin/env bash
set -euo pipefail

: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"
: "${TARGET_ARCH:?TARGET_ARCH is required}"
: "${TARGET_SUBTARGET:?TARGET_SUBTARGET is required}"
: "${TARGET_DEVICE:?TARGET_DEVICE is required}"

if [ -z "${WEBDAV_URL:-}" ] || [ -z "${WEBDAV_USERNAME:-}" ] || [ -z "${WEBDAV_PASSWORD:-}" ]; then
  echo "WebDAV upload requested but WEBDAV_URL/WEBDAV_USERNAME/WEBDAV_PASSWORD is incomplete"
  exit 1
fi

OUTPUT_DIR="$WORKSPACE_DIR/firmware-output"
if [ ! -d "$OUTPUT_DIR" ]; then
  echo "firmware-output not found"
  exit 1
fi

base_url="${WEBDAV_URL%/}"
base_path="${WEBDAV_PATH:-/openwrt}"
base_path="/${base_path#/}"
base_path="${base_path%/}"
remote_dir="$base_path/$TARGET_ARCH/$TARGET_SUBTARGET/$TARGET_DEVICE/$(date +%Y%m%d-%H%M%S)"

urlencode_path() {
  python3 - "$1" <<'PY'
from urllib.parse import quote
import sys
parts = [quote(part, safe='') for part in sys.argv[1].strip('/').split('/') if part]
print('/'.join(parts))
PY
}

mkdir_webdav_dir() {
  local path="$1"
  local current=""
  IFS='/' read -ra parts <<< "${path#/}"
  for part in "${parts[@]}"; do
    [ -z "$part" ] && continue
    current="$current/$part"
    encoded="$(urlencode_path "$current")"
    curl -fsS --retry 3 -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -X MKCOL "$base_url/$encoded" || true
  done
}

mkdir_webdav_dir "$remote_dir"
encoded_dir="$(urlencode_path "$remote_dir")"
failures=0
uploaded=0

shopt -s nullglob
for file in "$OUTPUT_DIR"/*; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  encoded_name="$(urlencode_path "$name")"
  echo "Uploading $name"
  if curl -fS --retry 3 -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "$file" "$base_url/$encoded_dir/$encoded_name"; then
    uploaded=$((uploaded + 1))
  else
    echo "Failed to upload $name"
    failures=$((failures + 1))
  fi
done

if [ "$uploaded" -eq 0 ]; then
  echo "No files uploaded to WebDAV"
  exit 1
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures file(s) failed to upload to WebDAV"
  exit 1
fi

echo "Uploaded $uploaded file(s) to WebDAV: $remote_dir"
