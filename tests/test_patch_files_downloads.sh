#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace_dir="$tmp_dir/workspace"
openwrt_dir="$tmp_dir/openwrt"
fake_bin="$tmp_dir/bin"
curl_log="$tmp_dir/curl.log"
mkdir -p "$workspace_dir/scripts" "$openwrt_dir/files" "$fake_bin"
cp "$repo_root/scripts/patch_files.sh" "$workspace_dir/scripts/patch_files.sh"
cat > "$workspace_dir/applist" <<'EOF'
luci-app-nikki
luci-app-easytier
EOF

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
printf '%s\n' "$url" >> "$CURL_LOG"

if [ -z "$output" ]; then
  case "$url" in
    *vernesong/mihomo*)
      cat <<'JSON'
{"assets":[{"name":"mihomo-linux-amd64-alpha-smart-new.gz","browser_download_url":"https://example.test/mihomo.gz"}]}
JSON
      ;;
    *EasyTier/EasyTier*)
      cat <<'JSON'
{"tag_name":"v9.9.9","assets":[{"name":"easytier-linux-x86_64-v9.9.9.zip","browser_download_url":"https://example.test/easytier.zip"}]}
JSON
      ;;
    *) printf '{}\n' ;;
  esac
  exit 0
fi

case "$url" in
  *vernesong/mihomo*)
    cat > "$output" <<'JSON'
{"assets":[{"name":"mihomo-linux-amd64-alpha-smart-new.gz","browser_download_url":"https://example.test/mihomo.gz"}]}
JSON
    ;;
  *EasyTier/EasyTier*)
    cat > "$output" <<'JSON'
{"tag_name":"v9.9.9","assets":[{"name":"easytier-linux-x86_64-v9.9.9.zip","browser_download_url":"https://example.test/easytier.zip"}]}
JSON
    ;;
  *mihomo.gz)
    printf 'mihomo-bin\n' | gzip -c > "$output"
    ;;
  *easytier.zip)
    python3 - "$output" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for name in ("easytier-core", "easytier-cli", "easytier-web-embed"):
        z.writestr(f"easytier-linux-x86_64/{name}", name + "\n")
PY
    ;;
  *zashboard*)
    python3 - "$output" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("dist/index.html", "ui\n")
PY
    ;;
  *)
    printf 'data\n' > "$output"
    ;;
esac
SH
chmod +x "$fake_bin/curl"

PATH="$fake_bin:$PATH" OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" TARGET_ARCH=x86 CURL_LOG="$curl_log" \
  bash "$workspace_dir/scripts/patch_files.sh"
rm -rf "$openwrt_dir/files"
mkdir -p "$openwrt_dir/files"
PATH="$fake_bin:$PATH" OPENWRT_DIR="$openwrt_dir" WORKSPACE_DIR="$workspace_dir" TARGET_ARCH=x86 CURL_LOG="$curl_log" \
  bash "$workspace_dir/scripts/patch_files.sh"

test -f "$openwrt_dir/files/usr/libexec/mihomo"
test -f "$openwrt_dir/files/usr/bin/easytier-core"
test -f "$openwrt_dir/files/usr/bin/easytier-cli"
test -f "$openwrt_dir/files/usr/bin/easytier-web-embed"
test -f "$openwrt_dir/files/etc/nikki/run/geoip.dat"
test -f "$openwrt_dir/files/etc/nikki/run/geosite.dat"
test -f "$openwrt_dir/files/etc/nikki/run/Model.bin"
test -f "$openwrt_dir/files/etc/nikki/run/ui/zashboard/index.html"
if [ "$(wc -l < "$curl_log")" -gt 8 ]; then
  echo "patch downloads were not reused across variants" >&2
  cat "$curl_log" >&2
  exit 1
fi
