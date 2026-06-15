#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

cd "$OPENWRT_DIR"

openwrt_make() {
  env -u TARGET_ARCH make "$@"
}

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

run_full_build() {
  openwrt_make defconfig
  openwrt_make download -j8 V=s

  local threads
  threads="$(nproc)"
  echo "Building with $threads threads"
  if ! openwrt_make -j"$threads"; then
    echo "Parallel build failed; retrying with single thread and verbose log"
    openwrt_make -j1 V=s
  fi
}

clean_repack_outputs() {
  echo "Cleaning stale firmware images before repack"
  rm -rf bin/targets
  find build_dir/target-* -type f \( \
    -name '.built' -o \
    -name '.image' -o \
    -name 'root.*' -o \
    -name '*.img' -o \
    -name '*.img.gz' -o \
    -name '*.bin' -o \
    -name '*.vmdk' -o \
    -name '*.vdi' -o \
    -name '*.qcow2' -o \
    -name '*.vhdx' -o \
    -name '*.efi' \
  \) -delete 2>/dev/null || true
}

run_repack_build() {
  echo "Repacking firmware images for files variant: ${FILES_VARIANT_NAME:-default}"
  clean_repack_outputs
  if openwrt_make target/install V=s; then
    return 0
  fi
  echo "target/install failed; falling back to single-thread make for correctness"
  openwrt_make -j1 V=s
}

if [ "${USE_CCACHE:-true}" = "true" ]; then
  export CCACHE_DIR="$OPENWRT_DIR/.ccache"
  export PATH="/usr/lib/ccache:$PATH"
  mkdir -p "$CCACHE_DIR"
  ccache -s || true
fi

print_machine_info
bash "$WORKSPACE_DIR/scripts/apply_files.sh" prepare
variant_total="$(grep -c '^[^[:space:]]' "$WORKSPACE_DIR/files-variants/variants.tsv")"

variant_count=0
while IFS=$'\t' read -r variant_name _zip_path; do
  [ -n "$variant_name" ] || continue
  variant_count=$((variant_count + 1))
  export FILES_VARIANT_NAME="$variant_name"
  export FILES_VARIANT_PREFIX=""
  if [ "$variant_total" -gt 1 ]; then
    export FILES_VARIANT_PREFIX="$variant_name"
  fi

  bash "$WORKSPACE_DIR/scripts/apply_files.sh" apply "$variant_name"

  if [ "$variant_count" -eq 1 ]; then
    run_full_build
  else
    run_repack_build
  fi

  bash "$WORKSPACE_DIR/scripts/filter_firmware.sh"
done < "$WORKSPACE_DIR/files-variants/variants.tsv"

if [ "$variant_count" -eq 0 ]; then
  echo "No files variants found"
  exit 1
fi

if [ "${USE_CCACHE:-true}" = "true" ]; then
  ccache -s || true
fi
print_machine_info
