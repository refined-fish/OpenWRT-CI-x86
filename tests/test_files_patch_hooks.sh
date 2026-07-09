#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace_dir="$tmp_dir/workspace"
openwrt_dir="$tmp_dir/openwrt"
mkdir -p "$workspace_dir/scripts" "$workspace_dir/files-variants" "$openwrt_dir"
cp "$repo_root/scripts/apply_files.sh" "$workspace_dir/scripts/apply_files.sh"

cat > "$workspace_dir/files-variants/variants.tsv" <<'EOF'
first	
second	
EOF

cat > "$workspace_dir/scripts/patch_files.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$OPENWRT_DIR/files/usr/libexec"
printf '%s\n' "${FILES_VARIANT_NAME:-missing}" >> "$OPENWRT_DIR/files/usr/libexec/patch-marker"
SH
chmod +x "$workspace_dir/scripts/patch_files.sh"

OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" FILES_VARIANT_NAME=first \
  bash "$workspace_dir/scripts/apply_files.sh" apply first
OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" FILES_VARIANT_NAME=second \
  bash "$workspace_dir/scripts/apply_files.sh" apply second

marker="$openwrt_dir/files/usr/libexec/patch-marker"
if ! grep -qx 'second' "$marker"; then
  echo "patch hook did not run after applying each files variant" >&2
  cat "$marker" >&2 2>/dev/null || true
  exit 1
fi
