#!/usr/bin/env python3
import re
import sys
from pathlib import Path

import yaml


def require(value, name):
    if value is None or str(value).strip() == "":
        raise SystemExit(f"Missing required config value: {name}")
    return str(value).strip()


def env_escape(value):
    return str(value).replace("\n", " ").strip()


def slugify(value):
    value = re.sub(r"^https?://", "", value)
    value = re.sub(r"\.git$", "", value)
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: parse_config.py <config.yaml> <github_env>")

    config_path = Path(sys.argv[1])
    env_path = Path(sys.argv[2])

    if not config_path.exists():
        raise SystemExit("config.yaml not found")

    data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}

    source = data.get("source") or {}
    target = data.get("target") or {}
    build = data.get("build") or {}
    upload = data.get("upload") or {}

    source_repo = require(source.get("repo"), "source.repo")
    source_branch = require(source.get("branch"), "source.branch")
    target_arch = require(target.get("arch"), "target.arch")
    target_subtarget = require(target.get("subtarget"), "target.subtarget")
    target_device = require(target.get("device"), "target.device")

    language = str(build.get("language") or "zh-cn").strip()
    rootfs_size_mb = str(build.get("rootfs_size_mb") or "").strip()
    grub_timeout = str(build.get("grub_timeout") or "").strip()
    use_ccache = str(build.get("use_ccache", True)).lower() in ("1", "true", "yes", "on")
    webdav_path = str(upload.get("webdav_path") or "/openwrt").strip()

    entries = {
        "SOURCE_REPO": source_repo,
        "SOURCE_BRANCH": source_branch,
        "SOURCE_REPO_SLUG": slugify(source_repo),
        "TARGET_ARCH": target_arch,
        "TARGET_SUBTARGET": target_subtarget,
        "TARGET_DEVICE": target_device,
        "BUILD_LANGUAGE": language,
        "ROOTFS_SIZE_MB": rootfs_size_mb,
        "GRUB_TIMEOUT": grub_timeout,
        "USE_CCACHE": "true" if use_ccache else "false",
        "WEBDAV_PATH": webdav_path,
    }

    with env_path.open("a", encoding="utf-8") as env_file:
        for key, value in entries.items():
            env_file.write(f"{key}={env_escape(value)}\n")

    print("Parsed config.yaml")
    for key in entries:
        print(f"{key}={entries[key]}")


if __name__ == "__main__":
    main()
