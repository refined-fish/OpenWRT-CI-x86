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
begin_marker = '# BEGIN OpenWRT-CI custom feeds'
end_marker = '# END OpenWRT-CI custom feeds'

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

existing_lines = feeds_file.read_text(encoding='utf-8').splitlines(keepends=True) if feeds_file.exists() else []
next_lines = []
inside_block = False
removed_block = False

for line in existing_lines:
    if line.rstrip('\n') == begin_marker:
        inside_block = True
        removed_block = True
        continue
    if inside_block:
        if line.rstrip('\n') == end_marker:
            inside_block = False
        continue
    next_lines.append(line)

while next_lines and not next_lines[-1].strip():
    next_lines.pop()

if lines:
    if next_lines:
        next_lines.append('\n')
    next_lines.append(f'{begin_marker}\n')
    next_lines.extend(lines)
    next_lines.append(f'{end_marker}\n')
    feeds_file.write_text(''.join(next_lines), encoding='utf-8')
    print('Configured custom feeds:')
    print(''.join(lines))
else:
    if removed_block:
        feeds_file.write_text(''.join(next_lines), encoding='utf-8')
    print('No custom feeds configured')
PY

./scripts/feeds update -a
./scripts/feeds install -a

python3 - <<'PY' > "$WORKSPACE_DIR/extra-packages.tsv"
from pathlib import PurePosixPath
import yaml

from os import environ
from pathlib import Path
import sys

sys.stdout.reconfigure(newline="\n")

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

reclone_extra_package() {
  local name="$1"
  local url="$2"
  local branch="$3"
  local dir="$4"
  local dest="$5"

  echo "Cloning extra package $name to $dir"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"

  local clone_args=(--depth 1)
  if [ -n "$branch" ]; then
    clone_args+=(--branch "$branch")
  fi

  git clone "${clone_args[@]}" "$url" "$dest"
}

remote_matches() {
  local dest="$1"
  local url="$2"
  local remote_url

  remote_url="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
  if [ "$remote_url" = "$url" ]; then
    return 0
  fi

  if [ -e "$url" ] || [ -e "$remote_url" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      [ "$(cygpath -m "$remote_url")" = "$(cygpath -m "$url")" ]
    else
      [ "$(realpath -m "$remote_url")" = "$(realpath -m "$url")" ]
    fi
  else
    return 1
  fi
}

reset_to_origin_head() {
  local dest="$1"
  local branch="$2"

  git -C "$dest" fetch --depth 1 origin || return
  if [ -n "$branch" ]; then
    git -C "$dest" reset --hard "origin/$branch"
  else
    local remote_head
    remote_head="$(git -C "$dest" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -n "$remote_head" ]; then
      git -C "$dest" reset --hard "$remote_head"
    else
      git -C "$dest" reset --hard FETCH_HEAD
    fi
  fi
}

update_or_reclone_extra_package() {
  local name="$1"
  local url="$2"
  local branch="$3"
  local dir="$4"
  local dest="$5"

  if [ ! -e "$dest" ]; then
    reclone_extra_package "$name" "$url" "$branch" "$dir" "$dest"
    return
  fi

  if [ ! -d "$dest/.git" ]; then
    echo "Recloning extra package $name because $dir is not a git repository"
    reclone_extra_package "$name" "$url" "$branch" "$dir" "$dest"
    return
  fi

  if ! remote_matches "$dest" "$url"; then
    echo "Recloning extra package $name because origin URL changed"
    reclone_extra_package "$name" "$url" "$branch" "$dir" "$dest"
    return
  fi

  echo "Updating extra package $name in $dir"
  if reset_to_origin_head "$dest" "$branch"; then
    return
  fi

  echo "Recloning extra package $name because fetch/reset failed"
  reclone_extra_package "$name" "$url" "$branch" "$dir" "$dest"
}

if [ -s "$WORKSPACE_DIR/extra-packages.tsv" ]; then
  while IFS=$'\x1f' read -r name url branch dir; do
    name="${name%$'\r'}"
    url="${url%$'\r'}"
    branch="${branch%$'\r'}"
    dir="${dir%$'\r'}"
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
    update_or_reclone_extra_package "$name" "$url" "$branch" "$dir" "$dest"
  done < "$WORKSPACE_DIR/extra-packages.tsv"
else
  echo "No extra packages configured"
fi
