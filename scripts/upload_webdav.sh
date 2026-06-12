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
print('/'.join(quote(part) for part in sys.argv[1].strip('/').split('/')))
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
    curl -fsS -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -X MKCOL "$base_url/$encoded" || true
  done
}

mkdir_webdav_dir "$remote_dir"

shopt -s nullglob
for file in "$OUTPUT_DIR"/*; do
  name="$(basename "$file")"
  encoded_dir="$(urlencode_path "$remote_dir")"
  encoded_name="$(python3 - <<PY
from urllib.parse import quote
print(quote('$name'))
PY
)"
  echo "Uploading $name"
  curl -fS --retry 3 -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "$file" "$base_url/$encoded_dir/$encoded_name"
done

echo "Uploaded firmware to WebDAV: $remote_dir"
