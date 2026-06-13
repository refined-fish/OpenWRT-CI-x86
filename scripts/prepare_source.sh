#!/usr/bin/env bash
set -euo pipefail

: "${SOURCE_REPO:?SOURCE_REPO is required}"
: "${SOURCE_BRANCH:?SOURCE_BRANCH is required}"
: "${OPENWRT_DIR:?OPENWRT_DIR is required}"

if [ -d "$OPENWRT_DIR" ]; then
  echo "OpenWrt source already exists: $OPENWRT_DIR"
  exit 0
fi

git clone --depth 1 --branch "$SOURCE_BRANCH" "$SOURCE_REPO" "$OPENWRT_DIR"

# Remove download mirrors that may fail on GitHub Actions runners
PROJECT_MIRRORS_FILE="$OPENWRT_DIR/scripts/projectsmirrors.json"
if [ -f "$PROJECT_MIRRORS_FILE" ]; then
  sed -i '/\.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
  echo "Removed restricted mirrors from projectsmirrors.json"
fi
