#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace_dir="$tmp_dir/workspace"
openwrt_dir="$tmp_dir/openwrt"
fake_bin="$tmp_dir/bin"
log_file="$tmp_dir/run.log"
mkdir -p "$workspace_dir/scripts" "$openwrt_dir/files" "$fake_bin"
cp "$repo_root/scripts/patch_files.sh" "$workspace_dir/scripts/patch_files.sh"
printf 'luci-app-nikki\n' > "$workspace_dir/applist"

cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

case "$url" in
  *api.github.com/repos/vernesong/mihomo*)
    if [ -n "$output" ]; then
      printf '{"assets":[]}\n' > "$output"
    else
      printf '{"assets":[]}\n'
    fi
    ;;
  *vernesong/mihomo/releases/download/Prerelease-Alpha/*)
    echo "unexpected fixed mihomo fallback: $url" >&2
    exit 44
    ;;
  *)
    [ -n "$output" ] && printf 'data\n' > "$output"
    ;;
esac
SH
chmod +x "$fake_bin/curl"

if PATH="$fake_bin:$PATH" OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" TARGET_ARCH=x86 \
  bash "$workspace_dir/scripts/patch_files.sh" >"$log_file" 2>&1; then
  echo "patch_files.sh should fail when the mihomo smart release asset is missing" >&2
  exit 1
fi

grep -q "No release asset matched mihomo-linux-amd64.*smart" "$log_file"
if grep -q "unexpected fixed mihomo fallback" "$log_file"; then
  cat "$log_file" >&2
  exit 1
fi
