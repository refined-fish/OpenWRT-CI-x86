#!/usr/bin/env python3
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[1]
base = root.parent
zip_path = base / "openwrt-ci-repo.zip"

exclude_parts = {"openwrt", "firmware-output", "__pycache__"}

if zip_path.exists():
    zip_path.unlink()

with ZipFile(zip_path, "w", ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(base)
        repo_relative = path.relative_to(root)
        if any(part in exclude_parts for part in repo_relative.parts):
            continue
        if path.suffix == ".zip":
            continue
        if path.is_file():
            archive.write(path, relative.as_posix())

print(zip_path)
