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

python3 - <<'PY' > "$WORKSPACE_DIR/extra-packages.tsv"
from pathlib import PurePosixPath
import yaml

from os import environ
from pathlib import Path

workspace = Path(environ["WORKSPACE_DIR"])
config = yaml.safe_load((workspace / "config.yaml").read_text(encoding="utf-8")) or {}
separator = "\x1f"

for item in config.get("extra_packages") or []:
    if not isinstance(item, dict):
        continue
    name = str(item.get("name") or "").strip()
    url = str(item.get("url") or "").strip()
    branch = str(item.get("branch") or "").strip()
    directory = str(item.get("dir") or "").strip().replace("\\", "/")
    if not url or not directory:
        raise SystemExit("extra_packages entries require url and dir")
    path = PurePosixPath(directory)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise SystemExit(f"Unsafe extra_packages dir: {directory}")
    if not name:
        name = path.name
    print(separator.join([name, url, branch, directory]))
PY

if [ -s "$WORKSPACE_DIR/extra-packages.tsv" ]; then
  while IFS=$'\x1f' read -r name url branch dir; do
    [ -n "$url" ] || continue
    if [ -z "$dir" ]; then
      echo "extra package $name has empty destination dir; refuse to continue"
      exit 1
    fi
    dest="$OPENWRT_DIR/$dir"
    case "$(realpath -m "$dest")" in
      "$(realpath -m "$OPENWRT_DIR")"/*) ;;
      *)
        echo "extra package $name destination escapes OPENWRT_DIR: $dir"
        exit 1
        ;;
    esac
    echo "Cloning extra package $name to $dir"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    clone_args=(--depth 1)
    if [ -n "$branch" ]; then
      clone_args+=(--branch "$branch")
    fi
    git clone "${clone_args[@]}" "$url" "$dest"
  done < "$WORKSPACE_DIR/extra-packages.tsv"
else
  echo "No extra packages configured"
fi
