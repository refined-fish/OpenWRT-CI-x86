#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"
: "${TARGET_ARCH:?TARGET_ARCH is required}"
: "${TARGET_SUBTARGET_SYMBOL:?TARGET_SUBTARGET_SYMBOL is required}"
: "${TARGET_DEVICE_SYMBOL:?TARGET_DEVICE_SYMBOL is required}"

CONFIG_FILE="$WORKSPACE_DIR/config/.config"
TARGET_CONFIG="$OPENWRT_DIR/.config"

openwrt_make() {
  env -u TARGET_ARCH make "$@"
}

append_bool_config() {
  local symbol="$1"
  local enabled="$2"
  if [ "$enabled" = "true" ]; then
    echo "${symbol}=y" >> "$TARGET_CONFIG"
  else
    echo "# ${symbol#CONFIG_} is not set" >> "$TARGET_CONFIG"
  fi
}

append_if_symbol_exists() {
  local symbol="$1"
  local enabled="$2"
  if grep -R "config ${symbol#CONFIG_}" -n target package 2>/dev/null | head -n 1 >/dev/null; then
    append_bool_config "$symbol" "$enabled"
  else
    echo "Skip unavailable image option: $symbol"
  fi
}

cd "$OPENWRT_DIR"

if [ -f "$CONFIG_FILE" ]; then
  echo "Using existing config/.config"
  cp "$CONFIG_FILE" "$TARGET_CONFIG"
else
  echo "config/.config not found; generating seed config from config.yaml and applist"
  : > "$TARGET_CONFIG"
  {
    echo "CONFIG_TARGET_${TARGET_ARCH}=y"
    echo "CONFIG_TARGET_${TARGET_ARCH}_${TARGET_SUBTARGET_SYMBOL}=y"
  } >> "$TARGET_CONFIG"

  if [ "${TARGET_MULTI_PROFILE:-false}" = "true" ]; then
    {
      echo "CONFIG_TARGET_MULTI_PROFILE=y"
      echo "CONFIG_TARGET_PER_DEVICE_ROOTFS=y"
    } >> "$TARGET_CONFIG"
    for device_symbol in ${TARGET_DEVICE_SYMBOLS:-}; do
      echo "CONFIG_TARGET_${TARGET_ARCH}_${TARGET_SUBTARGET_SYMBOL}_DEVICE_${device_symbol}=y" >> "$TARGET_CONFIG"
    done
  else
    echo "CONFIG_TARGET_${TARGET_ARCH}_${TARGET_SUBTARGET_SYMBOL}_DEVICE_${TARGET_DEVICE_SYMBOL}=y" >> "$TARGET_CONFIG"
  fi

  if [ "${BUILD_LANGUAGE:-zh-cn}" = "zh-cn" ]; then
    {
      echo "CONFIG_PACKAGE_luci=y"
      echo "CONFIG_LUCI_LANG_zh_Hans=y"
      echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y"
    } >> "$TARGET_CONFIG"
  fi

  if [ -f "$WORKSPACE_DIR/applist" ]; then
    while IFS= read -r package || [ -n "$package" ]; do
      package="${package%%#*}"
      package="$(echo "$package" | xargs)"
      [ -z "$package" ] && continue
      echo "CONFIG_PACKAGE_${package}=y" >> "$TARGET_CONFIG"
    done < "$WORKSPACE_DIR/applist"
  fi

  append_bool_config "CONFIG_TARGET_ROOTFS_EXT4FS" "${IMAGE_EXT4:-true}"
  append_bool_config "CONFIG_TARGET_ROOTFS_SQUASHFS" "${IMAGE_SQUASHFS:-true}"
  append_bool_config "CONFIG_TARGET_ROOTFS_INITRAMFS" "${IMAGE_INITRAMFS:-false}"

  if [ -n "${IMAGE_ROOTFS_SIZE_MB:-}" ]; then
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=${IMAGE_ROOTFS_SIZE_MB}" >> "$TARGET_CONFIG"
  fi
  if [ -n "${IMAGE_KERNEL_PARTITION_MB:-}" ]; then
    echo "CONFIG_TARGET_KERNEL_PARTSIZE=${IMAGE_KERNEL_PARTITION_MB}" >> "$TARGET_CONFIG"
  fi
  if [ -n "${GRUB_TIMEOUT:-}" ]; then
    echo "CONFIG_GRUB_TIMEOUT=\"${GRUB_TIMEOUT}\"" >> "$TARGET_CONFIG"
  fi

  if [[ "$TARGET_ARCH" == "x86" || "$TARGET_ARCH" == "x86_64" ]]; then
    append_bool_config "CONFIG_GRUB_IMAGES" "${IMAGE_LEGACY_BOOT:-true}"
    append_bool_config "CONFIG_EFI_IMAGES" "${IMAGE_UEFI_BOOT:-true}"
    append_if_symbol_exists "CONFIG_QCOW2_IMAGES" "${IMAGE_PVE:-false}"
    append_if_symbol_exists "CONFIG_VMDK_IMAGES" "${IMAGE_VMWARE:-false}"
    append_if_symbol_exists "CONFIG_VHDX_IMAGES" "${IMAGE_HYPERV:-false}"
  else
    echo "Skip x86-only image options for target arch: $TARGET_ARCH"
  fi
fi

if [ "${USE_CCACHE:-true}" = "true" ]; then
  echo "CONFIG_CCACHE=y" >> "$TARGET_CONFIG"
fi

echo "Generated seed .config:"
sed -n '1,180p' "$TARGET_CONFIG"

rm -f scripts/config/conf scripts/config/mconf scripts/config/nconf || true
if ! openwrt_make defconfig; then
  echo "make defconfig failed; retrying with single-thread verbose output"
  openwrt_make -j1 V=s defconfig
fi
