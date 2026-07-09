#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace_dir="$tmp_dir/workspace"
openwrt_dir="$tmp_dir/openwrt"
mkdir -p "$workspace_dir/scripts" "$openwrt_dir/scripts"
cp "$repo_root/scripts/prepare_feeds.sh" "$workspace_dir/scripts/prepare_feeds.sh"

cat > "$workspace_dir/config.yaml" <<'YAML'
feeds:
  - name: sqm-nss
    url: https://github.com/rickkdotnet/sqm-scripts-nss
    branch: main
YAML

cat > "$openwrt_dir/feeds.conf.default" <<'EOF'
src-git packages https://github.com/openwrt/packages.git
EOF

cat > "$openwrt_dir/scripts/feeds" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if grep -q '^src-git sqm-nss ' feeds.conf.default; then
  echo "invalid feed name was not sanitized" >&2
  exit 25
fi
grep -q '^src-git sqm_nss https://github.com/rickkdotnet/sqm-scripts-nss;main$' feeds.conf.default
SH
chmod +x "$openwrt_dir/scripts/feeds"

OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" bash "$workspace_dir/scripts/prepare_feeds.sh"
