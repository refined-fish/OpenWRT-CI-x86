#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace_dir="$tmp_dir/workspace"
openwrt_dir="$tmp_dir/openwrt"
fake_bin="$tmp_dir/bin"
mkdir -p "$workspace_dir/scripts" "$workspace_dir/files-variants" "$openwrt_dir/bin/targets/x86/64" "$fake_bin"
mkdir -p "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/linux-6.12.92/fs/proc"
printf 'kernel source sentinel\n' > "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/linux-6.12.92/fs/proc/root.c"
printf 'stale rootfs sentinel\n' > "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/root.squashfs"
touch "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/.image"
make_calls="$tmp_dir/make-calls.log"
cp "$repo_root/scripts/build_openwrt.sh" "$workspace_dir/scripts/build_openwrt.sh"

cat > "$workspace_dir/scripts/apply_files.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-prepare}" in
  prepare)
    mkdir -p "$WORKSPACE_DIR/files-variants"
    printf 'first\tfirst.zip\nsecond\tsecond.zip\n' > "$WORKSPACE_DIR/files-variants/variants.tsv"
    ;;
  apply)
    variant="${2:?variant is required}"
    rm -rf "$OPENWRT_DIR/files"
    mkdir -p "$OPENWRT_DIR/files/etc/config"
    printf 'variant=%s\n' "$variant" > "$OPENWRT_DIR/files/etc/config/variant"
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$workspace_dir/scripts/apply_files.sh"

cat > "$workspace_dir/scripts/filter_firmware.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$WORKSPACE_DIR/firmware-output"
prefix="${FILES_VARIANT_PREFIX:-}"
name="combined.img"
if [ -n "$prefix" ]; then
  name="$prefix-$name"
fi
cp "$OPENWRT_DIR/bin/targets/x86/64/combined.img" "$WORKSPACE_DIR/firmware-output/$name"
SH
chmod +x "$workspace_dir/scripts/filter_firmware.sh"

cat > "$fake_bin/lscpu" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin/lscpu"

cat > "$fake_bin/free" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin/free"

printf 'first\t%s\nsecond\t%s\n' \
  first.zip \
  second.zip \
  > "$workspace_dir/files-variants/variants.tsv"

cat > "$fake_bin/make" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

target="all"
for arg in "$@"; do
  case "$arg" in
    -*|V=*)
      ;;
    *)
      target="$arg"
      break
      ;;
  esac
done
stamp="$OPENWRT_DIR/.image-built"
firmware="$OPENWRT_DIR/bin/targets/x86/64/combined.img"
echo "$target" >> "$MAKE_CALLS_LOG"

case "$target" in
  defconfig|download)
    exit 0
    ;;
  target/install|all)
    if [ "$target" = "all" ] && [ ! -f "$firmware" ]; then
      mkdir -p "$(dirname "$firmware")"
      cp "$OPENWRT_DIR/files/etc/config/variant" "$firmware"
      touch "$stamp"
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fake_bin/make"

PATH="$fake_bin:$PATH" \
OPENWRT_DIR="$openwrt_dir" \
WORKSPACE_DIR="$workspace_dir" \
MAKE_CALLS_LOG="$make_calls" \
USE_CCACHE=false \
bash "$workspace_dir/scripts/build_openwrt.sh" >/tmp/test-files-variant-repack.log

first_image="$workspace_dir/firmware-output/first-combined.img"
second_image="$workspace_dir/firmware-output/second-combined.img"

if [ ! -f "$first_image" ] || [ ! -f "$second_image" ]; then
  echo "expected both variant images to be produced" >&2
  find "$workspace_dir/firmware-output" -type f -maxdepth 1 -print >&2 || true
  exit 1
fi

if ! grep -qx 'variant=first' "$first_image"; then
  echo "first image did not contain first variant files" >&2
  cat "$first_image" >&2
  exit 1
fi

if ! grep -qx 'variant=second' "$second_image"; then
  echo "second image reused stale files instead of second variant" >&2
  echo "second image content:" >&2
  cat "$second_image" >&2
  exit 1
fi

if [ ! -f "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/linux-6.12.92/fs/proc/root.c" ]; then
  echo "repack cleanup removed kernel source files" >&2
  exit 1
fi

if [ ! -f "$openwrt_dir/build_dir/target-x86_64_musl/linux-x86_64/root.squashfs" ]; then
  echo "repack cleanup unexpectedly removed build_dir rootfs artifacts" >&2
  exit 1
fi

if grep -qx 'target/install' "$make_calls"; then
  echo "repack used target/install instead of a full make invocation" >&2
  cat "$make_calls" >&2
  exit 1
fi

if [ "$(grep -cx 'all' "$make_calls")" -lt 2 ]; then
  echo "expected full make to run for the first build and repack" >&2
  cat "$make_calls" >&2
  exit 1
fi
