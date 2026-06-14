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
    find "$path" -type f -exec chmod 755 {} + 2>/dev/null || true
  fi
}

download_file() {
  local url="$1"
  local output="$2"
  echo "Downloading $url"
  curl -fL --retry 3 --connect-timeout 20 "$url" -o "$output"
  validate_zip "$output"
}

validate_zip() {
  local zip_path="$1"
  local py
  py="$(python_cmd)"
  "$py" - "$zip_path" <<'PY'
import sys
from zipfile import BadZipFile, ZipFile

zip_path = sys.argv[1]
try:
    with ZipFile(zip_path) as archive:
        bad = archive.testzip()
except BadZipFile as exc:
    raise SystemExit(f"Bad zip file: {exc}")
if bad:
    raise SystemExit(f"Corrupt member in zip file: {bad}")
print(f"Zip validated: {zip_path}")
PY
}

extract_zip_to_files() {
  local zip_path="$1"
  local output_dir="$2"
  local py
  py="$(python_cmd)"
  "$py" - "$zip_path" "$output_dir" <<'PY'
import os
import shutil
import stat
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

zip_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
text_suffixes = {
    '.sh', '.txt', '.conf', '.config', '.json', '.yaml', '.yml', '.ini', '.list', '.rules',
    '.network', '.firewall', '.dhcp', '.hotplug', '.uc', '.lua', '.js', '.css', '.html'
}

if output_dir.exists():
    shutil.rmtree(output_dir, ignore_errors=True)
output_dir.mkdir(parents=True, exist_ok=True)

def safe_name(info):
    if info.flag_bits & 0x800:
        best = info.filename
    else:
        raw = info.filename.encode('cp437', errors='replace')
        candidates = []
        for encoding in ('utf-8', 'gbk', 'cp936'):
            try:
                candidates.append(raw.decode(encoding))
            except UnicodeDecodeError:
                pass
        candidates.append(info.filename)
        best = max(candidates, key=lambda item: sum(ord(ch) > 127 for ch in item))
    best = best.replace('\\', '/')
    parts = []
    for part in PurePosixPath(best).parts:
        if part in ('', '.', '..'):
            continue
        parts.append(part)
    return PurePosixPath(*parts) if parts else None

def normalize_lf(path):
    try:
        data = path.read_bytes()
    except OSError:
        return
    if b'\0' in data:
        return
    if path.suffix.lower() not in text_suffixes:
        sample = data[:4096]
        if sample and sum(byte < 32 and byte not in (9, 10, 13) for byte in sample) > 0:
            return
    data = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    path.write_bytes(data)

with ZipFile(zip_path) as archive:
    for info in archive.infolist():
        rel = safe_name(info)
        if rel is None:
            continue
        target = output_dir / Path(*rel.parts)
        if not target.resolve().is_relative_to(output_dir.resolve()):
            raise SystemExit(f"Unsafe zip path: {info.filename}")
        mode = (info.external_attr >> 16) & 0o777
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            target.chmod(0o755)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, target.open('wb') as dest:
            shutil.copyfileobj(source, dest)
        normalize_lf(target)
        target.chmod(0o755)

for root, dirs, _files in os.walk(output_dir):
    for dirname in dirs:
        Path(root, dirname).chmod(0o755)
print(f"Extracted {zip_path} to {output_dir}")
PY
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

  if [ -z "$zip_path" ]; then
    rm -rf "$OPENWRT_DIR/files"
    mkdir -p "$OPENWRT_DIR/files"
    echo "No custom files for variant: $variant_name"
    return 0
  fi

  echo "Applying files variant: $variant_name"
  extract_zip_to_files "$zip_path" "$OPENWRT_DIR/files"
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
