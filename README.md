# OpenWrt CI Repo

个人自用的 OpenWrt GitHub Actions 编译仓库。使用 `config.yaml` 驱动 OpenWrt 单设备或多设备编译，支持自定义 `files.zip`、多预置文件变体、正式固件筛选、artifact 与 WebDAV 输出。

## 特性

- `config.yaml` 使用贴近 `make menuconfig` 的目标平台展示值，脚本自动转换为 OpenWrt Kconfig symbol。
- 支持 `target.device: multiple devices`，一次编译多个 target profile，并默认启用 per-device root filesystem。
- 支持从配置生成镜像选项：ext4/squashfs、initramfs、legacy/UEFI、分区大小、虚拟化平台镜像等。
- `files_zip_url` 可指向单个 zip，也可指向包含多个 zip 的目录；多个 zip 会生成同配置但不同预置文件的多份固件。
- 输出方式由 `config.yaml` 控制，默认仅上传 GitHub Actions artifact，可选 WebDAV 或二者同时启用。
- 敏感信息（WebDAV 凭据、`files.zip` 地址）只来自 GitHub Secrets 或手动触发输入，不写入仓库。

## 基础配置

```yaml
source:
  repo: https://github.com/immortalwrt/immortalwrt
  branch: openwrt-25.12

target:
  arch: x86
  subtarget: x86_64
  device: generic x86_64
```

`target.subtarget` 和 `target.device` 推荐填写 `make menuconfig` 中看到的展示值。脚本会自动转换，例如：

| 展示值 | Kconfig symbol |
|---|---|
| `subtarget: x86_64` | `64` |
| `device: generic x86_64` | `generic` |

## 多设备配置

当 target profile 选择 `multiple devices` 时，使用 `target.devices` 指定要编译的设备列表：

```yaml
target:
  arch: x86
  subtarget: x86_64
  device: multiple devices
  devices:
    - generic x86_64
```

多设备模式会自动写入：

```text
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
```

也就是默认启用 `Use a per-device root filesystem that adds profile packages`。

## 镜像配置

```yaml
image:
  filesystems:
    - ext4
    - squashfs
  initramfs: false
  recovery: false
  legacy_boot: true
  uefi_boot: true
  kernel_partition_mb: "16"
  rootfs_size_mb: "512"
  pve: false
  vmware: true
  hyperv: false
```

说明：

- `filesystems` 支持 `ext4`、`squashfs`。
- `legacy_boot` 控制传统 BIOS/legacy 引导镜像。
- `uefi_boot` 控制 UEFI 镜像。
- `kernel_partition_mb` 写入 `CONFIG_TARGET_KERNEL_PARTSIZE`。
- `rootfs_size_mb` 写入 `CONFIG_TARGET_ROOTFS_PARTSIZE`。
- `pve`、`vmware`、`hyperv` 仅在源码 Kconfig 存在对应镜像符号时写入，否则跳过并打印提示。

## 输出配置

默认只上传 artifact：

```yaml
output:
  artifact: true
  webdav: false
```

启用 WebDAV：

```yaml
output:
  artifact: true
  webdav: true

upload:
  webdav_path: /openwrt
```

启用 `webdav` 时，workflow 会在编译前检查：

- `upload.webdav_path`
- `WEBDAV_URL`
- `WEBDAV_USERNAME`
- `WEBDAV_PASSWORD`

如果缺失会早期失败，避免编译完成后才发现无法上传。

如果同时启用 artifact 和 WebDAV，WebDAV 失败时 artifact 保留为兜底。如果只启用 WebDAV，WebDAV 失败会让 workflow 失败。

## 第三方 feeds

```yaml
feeds:
  - name: nikki
    url: https://github.com/nikkinikki-org/OpenWrt-nikki
    branch: main
```

## 自定义软件包（applist）

如果没有提供 `config/.config`，请编辑仓库根目录下的 `applist`，一行一个软件包名：

```text
luci-app-ttyd
luci-app-upnp
curl
```

空行和 `#` 注释会被忽略，脚本会转换为 `CONFIG_PACKAGE_<name>=y` 并由 `make defconfig` 补全依赖。

## 自定义 files.zip

触发 workflow 时可填写 `files_zip_url`，也可设置仓库 Secret：`FILES_ZIP_URL`。手动输入优先。

### 单个 zip

如果链接指向单个 zip，脚本会下载并解压到 OpenWrt 源码根目录的 `files/`：

```text
files_zip_url=https://example.com/home.zip
```

zip 的首层必须就是要预置到固件根目录的内容，例如：

```text
etc/config/network
usr/bin/custom-script
```

不要再额外套一层顶层 `files/` 目录，脚本不会自动剥离它。

### 目录多 zip

如果链接指向目录，目录下的多个 `.zip` 表示多份预置文件变体：

```text
files_zip_url=https://example.com/openwrt-files/
```

目录需要能返回普通 HTTP/WebDAV listing，并在 HTML 中包含 `.zip` 链接。每个 zip 的文件名会成为变体名：

| zip | 固件名前缀 |
|---|---|
| `home.zip` | `home-` |
| `office.zip` | `office-` |

第一个变体执行完整编译，后续变体会替换 `openwrt/files/` 后尝试快速重包；如果目标 OpenWrt 版本不支持局部重包，会回退到可成功的保守构建路径。

## 产物说明

`firmware-output/` 中包含：

- 筛选后的正式固件
- `firmware-list.txt`：变体名、大小、固件文件名
- `build.config`：最终 `.config` 备份
- `build-info.txt`：源码、target 展示值、Kconfig symbol、image/output、files 变体信息

## Windows 编辑注意事项

本项目工作流运行在 Ubuntu，脚本和配置文件应使用 LF 换行符。

- 编辑器建议设置为 `LF`。
- `.gitattributes` 已强制 `*.sh`、`*.yml`、`*.yaml`、`applist` 使用 LF。
- workflow 会执行 `dos2unix` 和 `chmod +x` 作为二次保障。

## 使用方法

1. Fork 或上传本仓库到 GitHub。
2. 编辑 `config.yaml`。
3. 可选：放置 `config/.config` 成品配置；存在时脚本不会覆盖你的配置。
4. 若没有 `.config`，编辑 `applist` 和 `image` 配置。
5. 可选：设置 `FILES_ZIP_URL`、WebDAV 相关 Secrets。
6. 打开 Actions，运行 `OpenWrt CI`。
7. 从 artifact 或 WebDAV 获取固件。

## 清除缓存

手动运行 `OpenWrt CI` 时，将 `clean_cache` 设为 `true` 可跳过已有缓存并重新编译。

如果构建失败，workflow 会自动清理当前源码、分支、架构和 target 对应前缀的 `dl`、toolchain、ccache 缓存；不会清理其他架构或其他 target 的缓存。

## 故障排查

- 如果日志中出现 `cc -O2 x86 -c -o conf.o conf.c` 或 `cc: error: x86: No such file or directory`，通常是 `TARGET_ARCH` 环境变量污染了 GNU make 的内置规则。本项目脚本已通过 `env -u TARGET_ARCH make ...` 规避，新增脚本中不要直接调用裸 `make`。
- 如果目录形式的 `files_zip_url` 找不到 zip，请确认目录 listing 中能看到 `.zip` 链接；私有 WebDAV 目录需要用可匿名访问或带临时签名的 URL。
- 如果 zip 解压后固件中路径多了一层目录，请检查 zip 首层是否已经是固件根目录内容。
- 如果 zip 内中文文件名在 `unzip` 下出现 `mismatching "local" filename`，脚本会改用 Python 解压并自动尝试 UTF-8/GBK/CP936 文件名解码。
- `files.zip` 解压后会自动把文本配置和脚本转换为 LF；`files/` 下所有普通文件会自动加执行权限，避免 uci-defaults、init.d、bin 等脚本权限不足。
