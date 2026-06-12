#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
rm -f openwrt-ci-repo.zip
zip -r openwrt-ci-repo.zip openwrt-ci-repo \
  -x 'openwrt-ci-repo/openwrt/*' \
  -x 'openwrt-ci-repo/firmware-output/*' \
  -x 'openwrt-ci-repo/*.zip'

echo "Created openwrt-ci-repo.zip"
