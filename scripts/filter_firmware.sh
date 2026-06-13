#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

OUTPUT_DIR="$WORKSPACE_DIR/firmware-output"
TARGETS_DIR="$OPENWRT_DIR/bin/targets"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

if [ ! -d "$TARGETS_DIR" ]; then
  echo "No bin/targets directory found"
  exit 1
fi

is_blocked() {
  local name="$1"
  case "$name" in
    *initramfs*|*ramfs*|*ramdisk*|*recovery*|*rescue*|*failsafe*|*kernel*|*rootfs*|*Image*|*vmlinuz*|*uImage*|*zImage*|*dtb*|*manifest*|*buildinfo*|*json*|*sha256sums*|*packages*|*.elf|*.map|*.txt|*.log) return 0 ;;
    *) return 1 ;;
  esac
}

is_firmware() {
  local name="$1"
  case "$name" in
    *sysupgrade*.bin|*sysupgrade*.img|*sysupgrade*.img.gz|*factory*.bin|*factory*.img|*factory*.img.gz|*combined*.img|*combined*.img.gz|*.efi|*.vmdk|*.vdi|*.qcow2|*.img.gz|*.bin) return 0 ;;
    *) return 1 ;;
  esac
}

count=0
manifest_file="$OUTPUT_DIR/firmware-list.txt"
: > "$manifest_file"
while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  if is_blocked "$name"; then
    echo "Skip non-release artifact: $name"
    continue
  fi
  if is_firmware "$name"; then
    cp -f "$file" "$OUTPUT_DIR/"
    size="$(du -h "$file" | cut -f 1)"
    printf '%s\t%s\n' "$size" "$name" >> "$manifest_file"
    echo "Selected firmware: $name"
    count=$((count + 1))
  else
    echo "Skip unmatched file: $name"
  fi
done < <(find "$TARGETS_DIR" -maxdepth 5 -type f -print0)

if [ -f "$OPENWRT_DIR/.config" ]; then
  cp -f "$OPENWRT_DIR/.config" "$OUTPUT_DIR/build.config"
fi

{
  echo "source_repo=${SOURCE_REPO:-}"
  echo "source_branch=${SOURCE_BRANCH:-}"
  echo "target_arch=${TARGET_ARCH:-}"
  echo "target_subtarget=${TARGET_SUBTARGET:-}"
  echo "target_device=${TARGET_DEVICE:-}"
  echo "build_time=$(date '+%Y-%m-%d %H:%M:%S %Z')"
} > "$OUTPUT_DIR/build-info.txt"

if [ "$count" -eq 0 ]; then
  echo "No release firmware selected"
  find "$TARGETS_DIR" -maxdepth 5 -type f | sort
  exit 1
fi

printf 'Selected %s firmware file(s)\n' "$count"
ls -lh "$OUTPUT_DIR"
