#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

FILES_VARIANTS_DIR="$WORKSPACE_DIR/files-variants"
FILES_VARIANTS_LIST="$FILES_VARIANTS_DIR/variants.tsv"
PYTHON_BIN=""

python_cmd() {
  if [ -n "$PYTHON_BIN" ]; then
    printf '%s' "$PYTHON_BIN"
    return 0
  fi

  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys' >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"
        printf '%s' "$PYTHON_BIN"
        return 0
      fi
    fi
  done

  echo "No working Python interpreter found" >&2
  return 1
}

files_url() {
  local url="${FILES_ZIP_URL_INPUT:-}"
  if [ -z "$url" ]; then
    url="${FILES_ZIP_URL_SECRET:-}"
  fi
  printf '%s' "$url"
}

safe_variant_name() {
  local name="$1"
  name="${name%.zip}"
  name="$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9_.-]+/-/g; s/^-+|-+$//g')"
  [ -n "$name" ] || name="default"
  printf '%s' "$name"
}

cleanup_path_permissions() {
  local path="$1"
  if [ -e "$path" ]; then
    chmod -R u+rwX "$path" 2>/dev/null || true
  fi
}

download_file() {
  local url="$1"
  local output="$2"
  echo "Downloading $url"
  curl -fL --retry 3 --connect-timeout 20 "$url" -o "$output"
  unzip -tq "$output"
}

discover_directory_zips() {
  local url="$1"
  local py
  py="$(python_cmd)"
  "$py" - "$url" <<'PY'
from html.parser import HTMLParser
from urllib.parse import urljoin
import sys
import urllib.request

base = sys.argv[1]
if not base.endswith('/'):
    base += '/'

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        if tag.lower() != 'a':
            return
        attrs = dict(attrs)
        href = attrs.get('href')
        if href and href.lower().split('?', 1)[0].endswith('.zip'):
            self.links.append(urljoin(base, href))

with urllib.request.urlopen(base, timeout=30) as response:
    html = response.read().decode('utf-8', 'ignore')
parser = Parser()
parser.feed(html)
for link in sorted(set(parser.links)):
    print(link)
PY
}

prepare_variants() {
  local url
  url="$(files_url)"
  rm -rf "$FILES_VARIANTS_DIR"
  mkdir -p "$FILES_VARIANTS_DIR"
  : > "$FILES_VARIANTS_LIST"

  if [ -z "$url" ]; then
    echo -e "default\t" >> "$FILES_VARIANTS_LIST"
    echo "No files.zip URL provided; build without custom files"
    return 0
  fi

  if [[ "${url,,}" == *.zip* ]]; then
    local zip_path="$FILES_VARIANTS_DIR/default.zip"
    download_file "$url" "$zip_path"
    echo -e "default\t$zip_path" >> "$FILES_VARIANTS_LIST"
    echo "Prepared single files variant: default"
    return 0
  fi

  mapfile -t zip_urls < <(discover_directory_zips "$url")
  if [ "${#zip_urls[@]}" -eq 0 ]; then
    echo "No .zip files found under files directory URL: $url"
    echo "Provide a direct .zip URL or an HTTP/WebDAV directory listing that links to .zip files."
    exit 1
  fi

  local zip_url base name zip_path
  for zip_url in "${zip_urls[@]}"; do
    zip_url="${zip_url//$'\r'/}"
    [ -n "$zip_url" ] || continue
    base="$(basename "${zip_url%%\?*}")"
    name="$(safe_variant_name "$base")"
    zip_path="$FILES_VARIANTS_DIR/$name.zip"
    download_file "$zip_url" "$zip_path"
    echo -e "$name\t$zip_path" >> "$FILES_VARIANTS_LIST"
    echo "Prepared files variant: $name"
  done
}

apply_variant() {
  local variant_name="${1:-default}"
  local zip_path=""
  local found="false"
  if [ ! -f "$FILES_VARIANTS_LIST" ]; then
    echo "Files variants list not found; run: bash scripts/apply_files.sh prepare"
    exit 1
  fi

  while IFS=$'\t' read -r name path; do
    if [ "$name" = "$variant_name" ]; then
      zip_path="$path"
      found="true"
      break
    fi
  done < "$FILES_VARIANTS_LIST"

  if [ "$found" != "true" ]; then
    echo "Files variant not found: $variant_name"
    exit 1
  fi

  rm -rf "$OPENWRT_DIR/files"
  mkdir -p "$OPENWRT_DIR/files"

  if [ -z "$zip_path" ]; then
    echo "No custom files for variant: $variant_name"
    return 0
  fi

  echo "Applying files variant: $variant_name"
  unzip -oq "$zip_path" -d "$OPENWRT_DIR/files"
  cleanup_path_permissions "$OPENWRT_DIR/files"
  echo "Custom files applied to $OPENWRT_DIR/files"
}

case "${1:-prepare}" in
  prepare)
    prepare_variants
    ;;
  apply)
    apply_variant "${2:-default}"
    ;;
  list)
    if [ -f "$FILES_VARIANTS_LIST" ]; then
      cat "$FILES_VARIANTS_LIST"
    fi
    ;;
  *)
    echo "Usage: $0 {prepare|apply <variant>|list}"
    exit 2
    ;;
esac
