#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

APPLIST_FILE="$WORKSPACE_DIR/applist"
PATCH_CACHE_DIR="$WORKSPACE_DIR/files-patches"
FILES_DIR="$OPENWRT_DIR/files"

has_package() {
  local package="$1"
  [ -f "$APPLIST_FILE" ] || return 1
  sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$APPLIST_FILE" | grep -Fxq "$package"
}

download() {
  local url="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  echo "Downloading $url"
  curl -fL -o "$output" "$url"
}

asset_url() {
  local api_url="$1"
  local pattern="$2"
  local fallback="$3"
  local json url
  json="$(curl -fsSL "$api_url" 2>/dev/null || true)"
  if [ -n "$json" ]; then
    url="$(JSON="$json" python3 - "$pattern" <<'PY' 2>/dev/null || true
import json
import os
import re
import sys

pattern = re.compile(sys.argv[1])
data = json.loads(os.environ["JSON"])
for asset in data.get("assets", []):
    if pattern.search(asset.get("name", "")):
        print(asset.get("browser_download_url", ""))
        break
PY
)"
    if [ -n "$url" ]; then
      printf '%s\n' "$url"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
}

copy_overlay() {
  local source="$1"
  mkdir -p "$FILES_DIR"
  cp -a "$source"/. "$FILES_DIR"/
  chmod 755 "$FILES_DIR/usr/libexec/mihomo" "$FILES_DIR"/usr/bin/easytier-* 2>/dev/null || true
}

mihomo_arch() {
  case "${TARGET_ARCH:-}" in
    x86|x86_64) printf 'amd64' ;;
    *) printf 'arm64' ;;
  esac
}

easytier_arch() {
  case "${TARGET_ARCH:-}" in
    x86|x86_64) printf 'x86_64' ;;
    *) printf 'aarch64' ;;
  esac
}

easytier_web_name() {
  case "${TARGET_ARCH:-}" in
    x86|x86_64) printf 'easytier-web-embed' ;;
    *) printf 'easytier-web' ;;
  esac
}

mihomo_fallback_url() {
  case "$(mihomo_arch)" in
    amd64) printf 'https://github.com/vernesong/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-amd64-v2-go123-alpha-smart-1383218.gz' ;;
    *) printf 'https://github.com/vernesong/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-arm64-alpha-smart-19c497f.gz' ;;
  esac
}

prepare_nikki() {
  local cache="$PATCH_CACHE_DIR/nikki"
  local done_file="$cache/.done"
  if [ -f "$done_file" ]; then
    copy_overlay "$cache"
    return 0
  fi

  local tmp="$PATCH_CACHE_DIR/.tmp-nikki"
  local arch url
  arch="$(mihomo_arch)"
  rm -rf "$tmp" "$cache"
  mkdir -p "$tmp/root/usr/libexec" "$tmp/root/etc/nikki/run/ui"

  url="$(asset_url \
    "https://api.github.com/repos/vernesong/mihomo/releases/tags/Prerelease-Alpha" \
    "mihomo-linux-${arch}.*smart.*[.]gz$" \
    "$(mihomo_fallback_url)")"
  download "$url" "$tmp/mihomo.gz"
  gzip -dc "$tmp/mihomo.gz" > "$tmp/root/usr/libexec/mihomo"
  chmod 755 "$tmp/root/usr/libexec/mihomo"

  download "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat" "$tmp/root/etc/nikki/run/geoip.dat"
  download "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" "$tmp/root/etc/nikki/run/geosite.dat"
  download "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin" "$tmp/root/etc/nikki/run/Model.bin"
  download "https://github.com/Zephyruso/zashboard/releases/latest/download/dist-no-fonts.zip" "$tmp/zashboard.zip"
  unzip -q "$tmp/zashboard.zip" -d "$tmp/ui"
  mv "$tmp/ui/dist" "$tmp/root/etc/nikki/run/ui/zashboard"

  mv "$tmp/root" "$cache"
  touch "$done_file"
  rm -rf "$tmp"
  copy_overlay "$cache"
}

prepare_easytier() {
  local cache="$PATCH_CACHE_DIR/easytier"
  local done_file="$cache/.done"
  if [ -f "$done_file" ]; then
    copy_overlay "$cache"
    return 0
  fi

  local tmp="$PATCH_CACHE_DIR/.tmp-easytier"
  local arch url source_dir candidate
  arch="$(easytier_arch)"
  rm -rf "$tmp" "$cache"
  mkdir -p "$tmp/root/usr/bin"

  url="$(asset_url \
    "https://api.github.com/repos/EasyTier/EasyTier/releases/latest" \
    "easytier-linux-${arch}.*[.]zip$" \
    "https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-linux-${arch}-v2.6.4.zip")"
  download "$url" "$tmp/easytier.zip"
  unzip -q "$tmp/easytier.zip" -d "$tmp"
  source_dir=""
  for candidate in "$tmp"/easytier-linux-"$arch"*; do
    if [ -d "$candidate" ]; then
      source_dir="$candidate"
      break
    fi
  done
  [ -n "$source_dir" ] || { echo "EasyTier archive layout not found for $arch" >&2; exit 1; }
  install -m 0755 "$source_dir/easytier-core" "$tmp/root/usr/bin/easytier-core"
  install -m 0755 "$source_dir/easytier-cli" "$tmp/root/usr/bin/easytier-cli"
  install -m 0755 "$source_dir/easytier-web-embed" "$tmp/root/usr/bin/$(easytier_web_name)"

  mv "$tmp/root" "$cache"
  touch "$done_file"
  rm -rf "$tmp"
  copy_overlay "$cache"
}

mkdir -p "$PATCH_CACHE_DIR" "$FILES_DIR"
if has_package "luci-app-nikki"; then
  prepare_nikki
else
  echo "Skip nikki files patch: luci-app-nikki not in applist"
fi
if has_package "luci-app-easytier"; then
  prepare_easytier
else
  echo "Skip EasyTier files patch: luci-app-easytier not in applist"
fi
