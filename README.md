# openwrt-ci-fish

个人自用的 OpenWrt/ImmortalWrt GitHub Actions 编译仓库。目标是尽量复刻本地 `make menuconfig && make` 的编译流程，只把耗时构建放到 GitHub runner 上执行。

仓库只保留这几个入口：

- `.github/workflows/ci.yml`：手动触发的完整编译流程。
- `config.yaml`：源码、target、feeds、镜像和上传配置。
- `applist`：没有 `config/.config` 时追加的软件包列表。
- `config/.config`：可选，存在时优先使用手工配置。
- `scripts/`：workflow 调用的脚本。

## 使用方法

1. 编辑 `config.yaml`，确认源码、分支、架构、设备、feeds、额外包、镜像和输出方式。
2. 如果已有本地 `make menuconfig` 生成的配置，把它放到 `config/.config`。
3. 如果没有 `config/.config`，编辑 `applist`，一行一个 OpenWrt 包名。
4. 如需预置固件根目录文件，设置 GitHub Secret `FILES_ZIP_URL`。
5. 如需 WebDAV 上传，设置 `WEBDAV_URL`、`WEBDAV_USERNAME`、`WEBDAV_PASSWORD`。
6. 打开 GitHub Actions，手动运行 `OpenWrt CI`。

## config.yaml

源码配置：

```yaml
source:
  repo: "https://github.com/immortalwrt/immortalwrt"
  branch: "openwrt-25.12"
```

target 配置使用接近 `make menuconfig` 的展示值：

```yaml
target:
  arch: "x86"
  subtarget: "x86_64"
  device: "generic x86_64"
```

脚本会把 x86 常用展示值转换成 OpenWrt Kconfig symbol，例如 `x86_64` 转成 `64`，`generic x86_64` 转成 `generic`。

多设备编译写法：

```yaml
target:
  arch: "x86"
  subtarget: "x86_64"
  device: "multiple devices"
  devices:
    - "generic x86_64"
```

额外 feeds 会追加到 `feeds.conf.default` 后执行 `./scripts/feeds update -a` 和 `./scripts/feeds install -a`：

```yaml
feeds:
  - name: nikki
    url: https://github.com/nikkinikki-org/OpenWrt-nikki
    branch: main
```

不支持 feeds 的第三方包使用 `extra_packages` 克隆到 OpenWrt 源码目录内：

```yaml
extra_packages:
  - name: easytier
    url: https://github.com/EasyTier/luci-app-easytier
    dir: package/luci-app-easytier
```

`dir` 必须是源码目录内的相对路径。

镜像配置：

```yaml
image:
  filesystems:
    - squashfs
  initramfs: false
  recovery: false
  legacy_boot: false
  uefi_boot: true
  kernel_partition_mb: "32"
  rootfs_size_mb: "512"
  pve: false
  vmware: false
  hyperv: false
```

输出配置：

```yaml
output:
  artifact: false
  webdav: true

upload:
  webdav_path: /openwrt
  webdav_mode: bundle
```

至少启用 `artifact` 或 `webdav` 之一。启用 WebDAV 时必须设置对应 Secrets。

## .config 与 applist

如果 `config/.config` 存在，workflow 会直接复制它到 OpenWrt 源码根目录，执行 `make defconfig` 补全后开始编译。这种模式会跳过按 `config.yaml` 和 `applist` 生成配置的步骤，最接近本地已有配置复用。

如果 `config/.config` 不存在，脚本会生成一个 seed `.config`：

- 写入 target 架构、subtarget 和 device。
- 按 `build.language` 启用 LuCI 中文相关包。
- 读取 `applist` 中的软件包并写入 `CONFIG_PACKAGE_<name>=y`。
- 写入 `image` 中的 rootfs、引导和虚拟化镜像选项。
- 最后执行 `make defconfig` 补全依赖。

`applist` 支持空行和 `#` 注释。

## files.zip

`FILES_ZIP_URL` 是 GitHub Secret，指向一个 zip 或一个包含多个 zip 链接的 HTTP/WebDAV 目录。

单个 zip 时，内容会被解压到 OpenWrt 源码根目录的 `files/`。zip 首层应直接是固件根目录内容，例如：

```text
etc/config/network
usr/bin/custom-script
```

目录中存在多个 zip 时，每个 zip 会作为一个 files 变体。第一个变体执行完整编译，后续变体会清空并重新解压 `files/`，移出旧的 `bin/targets` 产物后再次执行完整 `make -j$(nproc) V=s`，让 OpenWrt 按当前 `files/` 内容增量生成新固件。输出固件会加上 zip 文件名对应的前缀。

zip 解压使用 Python 实现，会校验 zip、规避路径穿越、尝试处理 UTF-8/GBK 文件名，并把解压出的普通文件赋予可执行权限。

## 缓存

workflow 使用 `actions/cache` 恢复和保存：

- `dl`
- `staging_dir/host*`
- `staging_dir/tool*`
- `build_dir/host`
- `build_dir/toolchain-*`
- `staging_dir/target-*`
- `build_dir/target-*`
- `.ccache`

缓存策略偏乐观，适合短时间内重复编译、只增减软件包或替换 `files.zip` 的个人使用方式。缓存恢复只按当前源码仓库、分支和 target 前缀匹配，不再校验 OpenWrt 源码 hash、`config.yaml`、`applist` 或 `.config` 内容变化；如果确实更换架构、源码分支或做了大幅配置调整，请手动把 `clean_cache` 设为 `true`。`clean_cache` 设为 `true` 时会先删除当前源码、分支和 target 前缀下的旧缓存，跳过恢复，编译成功后仍保存新缓存。

如果编译失败，workflow 会用 `gh cache` 清理当前源码、分支和 target 前缀下的相关缓存，避免下次继续命中坏缓存。

## 上传

`artifact` 启用时，固件上传为 GitHub Actions artifact，保留 14 天。

`webdav` 启用时，固件会先打包成 `tar.zst`，再上传到：

```text
<WEBDAV_URL>/<upload.webdav_path>/<arch>/<subtarget>/<device>/<时间戳>/
```

`upload.webdav_mode` 默认为 `bundle`，会把 `firmware-output/` 打包成一个 `tar.zst` 上传；也可以设为 `direct` 逐文件上传。

需要设置 Secrets：

- `WEBDAV_URL`
- `WEBDAV_USERNAME`
- `WEBDAV_PASSWORD`

如果同时启用 artifact 和 WebDAV，WebDAV 失败不会导致整个 workflow 失败，artifact 会作为兜底产物。

## 本地文件规范

workflow 运行在 Ubuntu，脚本和配置文件需要使用 LF 换行。`.gitattributes` 已固定常用文本文件换行，workflow 也会在运行时对 shell 脚本执行 `dos2unix` 和 `chmod +x`。
