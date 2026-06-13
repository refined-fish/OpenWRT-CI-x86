#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"

cd "$OPENWRT_DIR"

print_machine_info() {
  echo "======================="
  lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core' || true
  echo "======================="
  free -h || true
  echo "======================="
  df -h || true
  echo "======================="
  du -h --max-depth=1 . 2>/dev/null | sort -h || true
  echo "======================="
}

if [ "${USE_CCACHE:-true}" = "true" ]; then
  export CCACHE_DIR="$OPENWRT_DIR/.ccache"
  export PATH="/usr/lib/ccache:$PATH"
  mkdir -p "$CCACHE_DIR"
  ccache -s || true
fi

print_machine_info
make defconfig
make download -j8 V=s

THREADS="$(nproc)"
echo "Building with $THREADS threads"
if ! make -j"$THREADS"; then
  echo "Parallel build failed; retrying with single thread and verbose log"
  make -j1 V=s
fi

if [ "${USE_CCACHE:-true}" = "true" ]; then
  ccache -s || true
fi
print_machine_info
