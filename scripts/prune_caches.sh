#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <family> <prefix> <saved-key> <save-outcome>" >&2
}

warn() {
  echo "::warning::$*"
}

if [ "$#" -ne 4 ]; then
  usage
  exit 2
fi

family="$1"
prefix="$2"
saved_key="$3"
save_outcome="$4"

case "$family" in
  dl|toolchain|target|feeds|ccache) ;;
  *)
    usage
    echo "Invalid cache family: $family" >&2
    exit 2
    ;;
esac

if [ -z "$prefix" ]; then
  usage
  echo "Cache prefix must not be empty" >&2
  exit 2
fi

case "$saved_key" in
  "$prefix"*) ;;
  *)
    usage
    echo "Saved cache key must start with prefix: $prefix" >&2
    exit 2
    ;;
esac

if [ "$save_outcome" != "success" ]; then
  echo "Skipping cache prune for ${family}: save outcome is ${save_outcome}"
  exit 0
fi

if [ -z "${GH_TOKEN:-}" ]; then
  warn "Skipping cache prune for ${family}: GH_TOKEN is not set."
  exit 0
fi

prune_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if ! prune_start_epoch="$(date -u -d "$prune_start" +%s 2>/dev/null)"; then
  warn "Unable to parse prune start time ${prune_start}; continuing without pruning."
  exit 0
fi
tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' EXIT

if ! gh cache list --key "$prefix" --limit 1000 --json id,key,createdAt \
  --jq '.[] | [.id, .key, .createdAt] | @tsv' > "$tmp_list"; then
  warn "Unable to list ${family} caches for prefix ${prefix}; continuing without pruning."
  exit 0
fi

while IFS=$'\t' read -r cache_id cache_key created_at; do
  [ -n "${cache_id:-}" ] || continue

  if [ "$cache_key" = "$saved_key" ]; then
    echo "Keeping current ${family} cache: ${cache_key}"
    continue
  fi

  case "$cache_key" in
    "$prefix"*) ;;
    *)
      echo "Skipping non-matching ${family} cache: ${cache_key}"
      continue
      ;;
  esac

  if [ -z "${created_at:-}" ]; then
    warn "Skipping ${family} cache with unknown createdAt: ${cache_key}"
    continue
  fi

  if ! created_epoch="$(date -u -d "$created_at" +%s 2>/dev/null)"; then
    warn "Skipping ${family} cache with unparseable createdAt ${created_at}: ${cache_key}"
    continue
  fi

  if [ "$created_epoch" -ge "$prune_start_epoch" ]; then
    echo "Keeping ${family} cache created during or after prune start: ${cache_key}"
    continue
  fi

  echo "Deleting old ${family} cache: ${cache_key}"
  if ! gh cache delete "$cache_id"; then
    warn "Unable to delete ${family} cache ${cache_key}; continuing."
  fi
done < "$tmp_list"
