#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"
: "${TARGET_ARCH:?TARGET_ARCH is required}"
: "${TARGET_SUBTARGET:?TARGET_SUBTARGET is required}"
: "${TARGET_DEVICE:?TARGET_DEVICE is required}"

CONFIG_FILE="$WORKSPACE_DIR/config/.config"
TARGET_CONFIG="$OPENWRT_DIR/.config"

cd "$OPENWRT_DIR"

if [ -f "$CONFIG_FILE" ]; then
  echo "Using existing config/.config"
  cp "$CONFIG_FILE" "$TARGET_CONFIG"
else
  echo "config/.config not found; generating seed config from config.yaml and applist"
  : > "$TARGET_CONFIG"
  {
    echo "CONFIG_TARGET_${TARGET_ARCH}=y"
    echo "CONFIG_TARGET_${TARGET_ARCH}_${TARGET_SUBTARGET}=y"
    echo "CONFIG_TARGET_${TARGET_ARCH}_${TARGET_SUBTARGET}_DEVICE_${TARGET_DEVICE}=y"
  } >> "$TARGET_CONFIG"

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
fi

if [[ "$TARGET_ARCH" == "x86" || "$TARGET_ARCH" == "x86_64" ]]; then
  if [ -n "${ROOTFS_SIZE_MB:-}" ]; then
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE_MB}" >> "$TARGET_CONFIG"
  fi
  if [ -n "${GRUB_TIMEOUT:-}" ]; then
    echo "CONFIG_GRUB_TIMEOUT=\"${GRUB_TIMEOUT}\"" >> "$TARGET_CONFIG"
  fi
else
  echo "Skip x86-only options for target arch: $TARGET_ARCH"
fi

if [ "${USE_CCACHE:-true}" = "true" ]; then
  echo "CONFIG_CCACHE=y" >> "$TARGET_CONFIG"
fi

echo "Generated seed .config:"
sed -n '1,120p' "$TARGET_CONFIG"

rm -f scripts/config/conf scripts/config/mconf scripts/config/nconf || true
if ! make defconfig; then
  echo "make defconfig failed; retrying with single-thread verbose output"
  make -j1 V=s defconfig
fi
