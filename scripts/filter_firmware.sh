#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

OUTPUT_DIR="$WORKSPACE_DIR/firmware-output"
TARGETS_DIR="$OPENWRT_DIR/bin/targets"
mkdir -p "$OUTPUT_DIR"

if [ ! -d "$TARGETS_DIR" ]; then
  echo "No bin/targets directory found"
  exit 1
fi

is_blocked() {
  local name="$1"
  case "$name" in
    *ramfs*|*ramdisk*|*failsafe*|*kernel*|*rootfs*|*Image*|*vmlinuz*|*uImage*|*zImage*|*dtb*|*manifest*|*buildinfo*|*json*|*sha256sums*|*packages*|*.elf|*.map|*.txt|*.log) return 0 ;;
  esac
  if [ "${IMAGE_INITRAMFS:-false}" != "true" ]; then
    case "$name" in *initramfs*) return 0 ;; esac
  fi
  if [ "${IMAGE_RECOVERY:-false}" != "true" ]; then
    case "$name" in *recovery*|*rescue*) return 0 ;; esac
  fi
  if [ "${IMAGE_EXT4:-true}" != "true" ]; then
    case "$name" in *ext4*) return 0 ;; esac
  fi
  if [ "${IMAGE_SQUASHFS:-true}" != "true" ]; then
    case "$name" in *squashfs*) return 0 ;; esac
  fi
  if [ "${IMAGE_UEFI_BOOT:-true}" != "true" ]; then
    case "$name" in *efi*) return 0 ;; esac
  fi
  if [ "${IMAGE_LEGACY_BOOT:-true}" != "true" ]; then
    case "$name" in *combined.img.gz|*combined.img) [[ "$name" != *efi* ]] && return 0 ;; esac
  fi
  return 1
}

is_firmware() {
  local name="$1"
  case "$name" in
    *sysupgrade*.bin|*sysupgrade*.img|*sysupgrade*.img.gz|*factory*.bin|*factory*.img|*factory*.img.gz|*combined*.img|*combined*.img.gz|*.efi|*.vmdk|*.vdi|*.qcow2|*.vhdx|*.img.gz|*.bin) return 0 ;;
    *) return 1 ;;
  esac
}

variant_name="${FILES_VARIANT_NAME:-default}"
variant_prefix="${FILES_VARIANT_PREFIX:-}"
manifest_file="$OUTPUT_DIR/firmware-list.txt"
info_file="$OUTPUT_DIR/build-info.txt"
touch "$manifest_file"
count=0

while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  if is_blocked "$name"; then
    echo "Skip non-release artifact: $name"
    continue
  fi
  if is_firmware "$name"; then
    output_name="$name"
    if [ -n "$variant_prefix" ]; then
      output_name="$variant_prefix-$name"
    fi
    cp -f "$file" "$OUTPUT_DIR/$output_name"
    size="$(du -h "$file" | cut -f 1)"
    printf '%s\t%s\t%s\n' "$variant_name" "$size" "$output_name" >> "$manifest_file"
    echo "Selected firmware: $output_name"
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
  echo "target_subtarget_symbol=${TARGET_SUBTARGET_SYMBOL:-}"
  echo "target_device=${TARGET_DEVICE:-}"
  echo "target_device_symbol=${TARGET_DEVICE_SYMBOL:-}"
  echo "target_device_symbols=${TARGET_DEVICE_SYMBOLS:-}"
  echo "target_multi_profile=${TARGET_MULTI_PROFILE:-false}"
  echo "image_filesystems=${IMAGE_FILESYSTEMS:-}"
  echo "image_initramfs=${IMAGE_INITRAMFS:-false}"
  echo "image_recovery=${IMAGE_RECOVERY:-false}"
  echo "image_legacy_boot=${IMAGE_LEGACY_BOOT:-true}"
  echo "image_uefi_boot=${IMAGE_UEFI_BOOT:-true}"
  echo "output_artifact=${OUTPUT_ARTIFACT:-true}"
  echo "output_webdav=${OUTPUT_WEBDAV:-false}"
  echo "last_files_variant=$variant_name"
  echo "build_time=$(date '+%Y-%m-%d %H:%M:%S %Z')"
} > "$info_file"

if [ "$count" -eq 0 ]; then
  echo "No release firmware selected for variant: $variant_name"
  find "$TARGETS_DIR" -maxdepth 5 -type f | sort
  exit 1
fi

printf 'Selected %s firmware file(s) for variant %s\n' "$count" "$variant_name"
ls -lh "$OUTPUT_DIR"
