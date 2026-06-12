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
