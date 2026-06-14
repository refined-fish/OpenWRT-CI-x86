#!/usr/bin/env python3
"""Parse config.yaml and emit GitHub Actions environment variables."""
import re
import sys
from pathlib import Path

import yaml


X86_SUBTARGETS = {
    "64": "64",
    "x86_64": "64",
}

X86_DEVICES = {
    "generic": "generic",
    "generic x86_64": "generic",
}


def require(value, name):
    if value is None or str(value).strip() == "":
        raise SystemExit(f"Missing required config value: {name}")
    return str(value).strip()


def env_escape(value):
    return str(value).replace("\n", " ").strip()


def slugify(value):
    value = re.sub(r"^https?://", "", str(value))
    value = re.sub(r"\.git$", "", value)
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-")


def parse_bool(raw, default=False):
    value = default if raw is None else raw
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "on", "y")


def parse_list(raw, default=None):
    if raw is None:
        return list(default or [])
    if isinstance(raw, (list, tuple)):
        return [str(item).strip() for item in raw if str(item).strip()]
    return [item.strip() for item in str(raw).split(",") if item.strip()]


def map_subtarget(arch, subtarget):
    if arch == "x86":
        return X86_SUBTARGETS.get(subtarget, subtarget)
    return subtarget.replace("-", "_").replace(" ", "_")


def map_device(arch, device):
    if arch == "x86":
        return X86_DEVICES.get(device, slugify(device).replace("-", "_"))
    return device.replace("-", "_").replace(" ", "_")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: parse_config.py <config.yaml> <github_env>")

    config_path = Path(sys.argv[1])
    env_path = Path(sys.argv[2])

    if not config_path.exists():
        raise SystemExit(f"{config_path} not found")

    data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}

    source = data.get("source") or {}
    target = data.get("target") or {}
    build = data.get("build") or {}
    image = data.get("image") or {}
    output = data.get("output") or {}
    upload = data.get("upload") or {}

    source_repo = require(source.get("repo"), "source.repo")
    source_branch = require(source.get("branch"), "source.branch")
    target_arch = require(target.get("arch"), "target.arch")
    target_subtarget = require(target.get("subtarget"), "target.subtarget")
    target_device = require(target.get("device"), "target.device")

    target_subtarget_symbol = map_subtarget(target_arch, target_subtarget)
    multi_profile = target_device.strip().lower() == "multiple devices"
    target_devices = parse_list(target.get("devices"))
    if multi_profile and not target_devices:
        raise SystemExit("target.devices is required when target.device is 'multiple devices'")

    if multi_profile:
        target_device_symbol = "multiple"
        target_device_symbols = [map_device(target_arch, device) for device in target_devices]
        target_device_slug = "multiple-devices"
    else:
        target_device_symbol = map_device(target_arch, target_device)
        target_device_symbols = [target_device_symbol]
        target_device_slug = slugify(target_device)

    language = str(build.get("language") or "zh-cn").strip()
    use_ccache = parse_bool(build.get("use_ccache"), True)

    image_filesystems = [item.lower() for item in parse_list(image.get("filesystems"), ["ext4", "squashfs"])]
    valid_filesystems = {"ext4", "squashfs"}
    unknown_filesystems = sorted(set(image_filesystems) - valid_filesystems)
    if unknown_filesystems:
        raise SystemExit(f"Unsupported image.filesystems value(s): {', '.join(unknown_filesystems)}")

    image_rootfs_size_mb = str(image.get("rootfs_size_mb") or build.get("rootfs_size_mb") or "").strip()
    image_kernel_partition_mb = str(image.get("kernel_partition_mb") or "").strip()
    grub_timeout = str(image.get("grub_timeout") or build.get("grub_timeout") or "").strip()

    output_artifact = parse_bool(output.get("artifact"), True)
    output_webdav = parse_bool(output.get("webdav"), False)
    if not output_artifact and not output_webdav:
        raise SystemExit("At least one output method must be enabled: output.artifact or output.webdav")

    webdav_path = str(upload.get("webdav_path") or "").strip()
    if output_webdav and not webdav_path:
        raise SystemExit("upload.webdav_path is required when output.webdav is true")
    if not webdav_path:
        webdav_path = "/openwrt"

    target_slug = slugify(f"{target_arch}-{target_subtarget}-{target_device_slug}")

    entries = {
        "SOURCE_REPO": source_repo,
        "SOURCE_BRANCH": source_branch,
        "SOURCE_REPO_SLUG": slugify(source_repo),
        "TARGET_ARCH": target_arch,
        "TARGET_SUBTARGET": target_subtarget,
        "TARGET_DEVICE": target_device,
        "TARGET_SUBTARGET_SYMBOL": target_subtarget_symbol,
        "TARGET_DEVICE_SYMBOL": target_device_symbol,
        "TARGET_DEVICE_SYMBOLS": " ".join(target_device_symbols),
        "TARGET_DEVICES": "|".join(target_devices),
        "TARGET_MULTI_PROFILE": "true" if multi_profile else "false",
        "TARGET_SLUG": target_slug,
        "BUILD_LANGUAGE": language,
        "USE_CCACHE": "true" if use_ccache else "false",
        "IMAGE_FILESYSTEMS": " ".join(image_filesystems),
        "IMAGE_EXT4": "true" if "ext4" in image_filesystems else "false",
        "IMAGE_SQUASHFS": "true" if "squashfs" in image_filesystems else "false",
        "IMAGE_INITRAMFS": "true" if parse_bool(image.get("initramfs"), False) else "false",
        "IMAGE_RECOVERY": "true" if parse_bool(image.get("recovery"), False) else "false",
        "IMAGE_LEGACY_BOOT": "true" if parse_bool(image.get("legacy_boot"), True) else "false",
        "IMAGE_UEFI_BOOT": "true" if parse_bool(image.get("uefi_boot"), True) else "false",
        "IMAGE_KERNEL_PARTITION_MB": image_kernel_partition_mb,
        "IMAGE_ROOTFS_SIZE_MB": image_rootfs_size_mb,
        "IMAGE_PVE": "true" if parse_bool(image.get("pve"), False) else "false",
        "IMAGE_VMWARE": "true" if parse_bool(image.get("vmware"), False) else "false",
        "IMAGE_HYPERV": "true" if parse_bool(image.get("hyperv"), False) else "false",
        "GRUB_TIMEOUT": grub_timeout,
        "OUTPUT_ARTIFACT": "true" if output_artifact else "false",
        "OUTPUT_WEBDAV": "true" if output_webdav else "false",
        "WEBDAV_PATH": webdav_path,
    }

    env_path.parent.mkdir(parents=True, exist_ok=True)
    with env_path.open("a", encoding="utf-8", newline="\n") as env_file:
        for key, value in entries.items():
            env_file.write(f"{key}={env_escape(value)}\n")

    print("Parsed config.yaml")
    for key in sorted(entries):
        print(f"  {key}={entries[key]}")


if __name__ == "__main__":
    main()
