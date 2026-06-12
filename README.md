# OpenWrt CI Repo

这是一个个人自用的 OpenWrt GitHub Actions 编译仓库模板。

## 特性

- 使用 `config.yaml` 指定 OpenWrt 源码、分支、目标架构、子架构、设备型号和第三方 feeds。
- 固定读取 `config/.config`；如果不存在，则根据 `config.yaml` 与 `applist` 动态生成最小 `.config`，再执行 `make defconfig` 补全依赖。
- 支持手动触发时传入一次性 `files.zip` 地址，也支持使用 `secrets.FILES_ZIP_URL`。
- 只上传筛选后的正式固件，排除 initramfs、recovery、rescue、kernel、rootfs 等临时或救砖相关产物。
- 支持 GitHub Actions artifact 与 WebDAV 上传。
- 敏感信息只从 GitHub Secrets 或手动触发输入读取，不从仓库文件读取。

## 必填配置

编辑 `config.yaml`：

```yaml
source:
  repo: https://github.com/openwrt/openwrt
  branch: main

target:
  arch: x86
  subtarget: 64
  device: generic
```

`source.repo`、`source.branch`、`target.arch`、`target.subtarget`、`target.device` 不提供默认值，必须自行确认。

## 自定义软件包

如果你没有上传 `config/.config`，请编辑 `applist`，一行一个软件包名，例如：

```text
luci-app-ttyd
luci-app-upnp
curl
```

生成配置时会转换为：

```text
CONFIG_PACKAGE_luci-app-ttyd=y
```

然后执行 `make defconfig` 补全依赖。

## 自定义 files

支持两种方式：

1. 手动运行 Actions 时填写 `files_zip_url`。
2. 设置仓库 Secret：`FILES_ZIP_URL`。

手动输入优先级高于 Secret。两者都为空时跳过。

## WebDAV Secrets

如需上传到 WebDAV，请设置：

- `WEBDAV_URL`
- `WEBDAV_USERNAME`
- `WEBDAV_PASSWORD`

远端基础路径由 `config.yaml` 的 `upload.webdav_path` 控制，默认 `/openwrt`。

## x86 特有配置

`build.rootfs_size_mb` 和 `build.grub_timeout` 只对 x86 目标生效；其他架构会自动跳过，不中断构建。

## 使用方法

1. Fork 或上传本仓库到 GitHub。
2. 编辑 `config.yaml`。
3. 可选：上传 `config/.config`。
4. 如果没有 `.config`，编辑 `applist`。
5. 在仓库 Settings 中配置 WebDAV / files.zip 相关 Secrets。
6. 打开 Actions，运行 `OpenWrt CI`。

## 产物规则

CI 会从 `bin/targets/**` 中筛选正式固件到 `firmware-output/`，并上传 artifact。启用 WebDAV 时，只上传该目录下的文件。
