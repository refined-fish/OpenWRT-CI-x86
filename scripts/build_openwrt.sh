#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"

cd "$OPENWRT_DIR"

if [ "${USE_CCACHE:-true}" = "true" ]; then
  export CCACHE_DIR="$OPENWRT_DIR/.ccache"
  export PATH="/usr/lib/ccache:$PATH"
  mkdir -p "$CCACHE_DIR"
fi

make defconfig
make download -j8 V=s

THREADS="$(nproc)"
echo "Building with $THREADS threads"
if ! make -j"$THREADS"; then
  echo "Parallel build failed; retrying with single thread and verbose log"
  make -j1 V=s
fi
