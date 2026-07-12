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

echo "Target firmware files before filtering:"
find "$TARGETS_DIR" -mindepth 3 -maxdepth 3 -type f | sort

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
    *sysupgrade*.bin|*sysupgrade*.img|*sysupgrade*.img.gz|*factory*.bin|*factory*.img|*factory*.img.gz|*combined*.img|*combined*.img.gz|*.efi|*.vmdk|*.vdi|*.qcow2|*.vhdx|*.img.gz|*.bin|*.ubi) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '_-'
}

variant_name="${FILES_VARIANT_NAME:-default}"
variant_prefix="${FILES_VARIANT_PREFIX:-}"
manifest_file="$OUTPUT_DIR/firmware-list.txt"
info_file="$OUTPUT_DIR/build-info.txt"
touch "$manifest_file"
count=0
requested_devices=(${TARGET_DEVICE_SYMBOLS:-})
declare -A device_counts=()
for device_symbol in "${requested_devices[@]}"; do
  device_counts["$device_symbol"]=0
done

while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  if is_blocked "$name"; then
    echo "Skip non-release artifact: $name"
    continue
  fi
  if is_firmware "$name"; then
    firmware_device="${TARGET_DEVICE_SYMBOL:-unknown}"
    if [ "${TARGET_MULTI_PROFILE:-false}" = "true" ]; then
      firmware_device=""
      matched_length=0
      normalized_name="$(normalize_name "$name")"
      for device_symbol in "${requested_devices[@]}"; do
        normalized_device="$(normalize_name "$device_symbol")"
        if [[ "$normalized_name" == *"$normalized_device"* ]] && [ "${#normalized_device}" -gt "$matched_length" ]; then
          firmware_device="$device_symbol"
          matched_length="${#normalized_device}"
        fi
      done
      if [ -z "$firmware_device" ]; then
        echo "Skip firmware for unrequested device: $name"
        continue
      fi
    elif [ "${#requested_devices[@]}" -gt 0 ]; then
      firmware_device="${requested_devices[0]}"
    fi
    output_name="$name"
    if [ -n "$variant_prefix" ]; then
      output_name="$variant_prefix-$name"
    fi
    cp -f "$file" "$OUTPUT_DIR/$output_name"
    size="$(du -h "$file" | cut -f 1)"
    printf '%s\t%s\t%s\t%s\n' "$variant_name" "$firmware_device" "$size" "$output_name" >> "$manifest_file"
    echo "Selected firmware: $output_name"
    count=$((count + 1))
    if [ "${#requested_devices[@]}" -gt 0 ]; then
      device_counts["$firmware_device"]=$((device_counts["$firmware_device"] + 1))
    fi
  else
    echo "Skip unmatched file: $name"
  fi
done < <(find "$TARGETS_DIR" -mindepth 3 -maxdepth 3 -type f -print0)

missing_device=false
for device_symbol in "${requested_devices[@]}"; do
  if [ "${device_counts[$device_symbol]}" -eq 0 ]; then
    echo "Missing release firmware for requested device: $device_symbol" >&2
    missing_device=true
  fi
done
[ "$missing_device" = false ] || exit 1

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
  find "$TARGETS_DIR" -mindepth 3 -maxdepth 3 -type f | sort
  exit 1
fi

printf 'Selected %s firmware file(s) for variant %s\n' "$count" "$variant_name"
ls -lh "$OUTPUT_DIR"
