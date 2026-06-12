#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?OPENWRT_DIR is required}"
: "${WORKSPACE_DIR:?WORKSPACE_DIR is required}"

cd "$OPENWRT_DIR"

python3 - <<'PY'
from pathlib import Path
import yaml

workspace = Path(__import__('os').environ['WORKSPACE_DIR'])
openwrt = Path(__import__('os').environ['OPENWRT_DIR'])
config = yaml.safe_load((workspace / 'config.yaml').read_text(encoding='utf-8')) or {}
feeds = config.get('feeds') or []
feeds_file = openwrt / 'feeds.conf.default'

lines = []
for feed in feeds:
    if not isinstance(feed, dict):
        continue
    name = str(feed.get('name') or '').strip()
    url = str(feed.get('url') or '').strip()
    branch = str(feed.get('branch') or '').strip()
    if not name or not url:
        continue
    if branch:
        lines.append(f"src-git {name} {url};{branch}\n")
    else:
        lines.append(f"src-git {name} {url}\n")

if lines:
    with feeds_file.open('a', encoding='utf-8') as handle:
        handle.write('\n# custom feeds from config.yaml\n')
        handle.writelines(lines)
    print('Appended custom feeds:')
    print(''.join(lines))
else:
    print('No custom feeds configured')
PY

./scripts/feeds update -a
./scripts/feeds install -a
