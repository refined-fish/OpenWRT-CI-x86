# OpenWrt CI Repo

个人自用的 OpenWrt GitHub Actions 编译仓库。继承 `OpenWRT-CI` 核心编译能力，固定搭配 `config.yaml`，支持单设备编译、`files.zip` 自定义文件、正式固件筛选及 WebDAV 上传。

## 特性

- `config.yaml` 统一指定源码、分支、目标平台、第三方 feeds、x86 专属选项、语言及 WebDAV 路径。
- 优先使用 `config/.config`；不存在时根据 `config.yaml` 目标三元组与 `applist` 生成最小种子 `.config`，再执行 `make defconfig` 补全依赖。
- 编译前通过 ImmortalWrt 官方一键脚本安装完整依赖，并启用工具链 / 下载 / ccache 三级缓存加速重复编译。
- 可选 `files.zip` 覆盖自定义文件；支持手动输入或仓库 Secret，不写入仓库。
- 仅筛选正式固件（sysupgrade / factory / combined / efi / vmdk），排除 initramfs、recovery、kernel 等非发布产物。
- 上传 artifact 并支持可选的 WebDAV 上传；WebDAV 失败时 artifact 保留为兜底，避免丢失产物。
- 所有敏感信息（WebDAV 凭据、`files.zip` 地址）仅通过 GitHub Secrets 或手动触发输入传入，不写入仓库文件。

## 必填配置

编辑 `config.yaml`，必须填写：

```yaml
source:
  repo: https://github.com/immortalwrt/immortalwrt
  branch: openwrt-25.12

target:
  arch: x86
  subtarget: "64"
  device: generic
```

`source.repo`、`source.branch`、`target.arch`、`target.subtarget`、`target.device` 无默认值，必须按你的实际平台填写。

## 可选配置

### 第三方 feeds

在 `config.yaml` 中追加 feeds（可选，多个条目）：

```yaml
feeds:
  - name: nikki
    url: https://github.com/nikkinikki-org/OpenWrt-nikki
    branch: main
```

### x86 专属选项

仅当 `target.arch` 为 `x86` 或 `x86_64` 时生效；其他架构自动跳过，不中断构建。

```yaml
build:
  rootfs_size_mb: "512"
  grub_timeout: "3"
```

### 语言与 ccache

```yaml
build:
  language: zh-cn        # 默认 zh-cn
  use_ccache: true       # 默认 true
```

### WebDAV 上传路径

```yaml
upload:
  webdav_path: /openwrt
```

固件会上传至 `{webdav_path}/{arch}/{subtarget}/{device}/{timestamp}/`。

## 自定义软件包（applist）

如果没有上传 `config/.config`，请编辑仓库根目录下的 `applist` 文件，一行一个软件包名，例如：

```text
luci-app-ttyd
luci-app-upnp
curl
```

`#` 开头的行为注释，空行会被忽略。生成配置时会自动转换为 `CONFIG_PACKAGE_<name>=y` 并写入种子 `.config`，再由 `make defconfig` 补全依赖。

## 自定义文件（files.zip）

支持两种方式，手动输入优先级高于 Secret。两者都为空时跳过此步骤。

1. **手动触发**：在 Actions 页面运行 `OpenWrt CI` 时填写 `files_zip_url`。
2. **仓库 Secret**：设置 `FILES_ZIP_URL` Secret。

`files.zip` 支持两种结构：
- 压缩包内直接含 `files/` 目录，目录内容将合并到 OpenWrt 编译目录的 `files/`。
- 压缩包内没有顶层 `files/` 目录，则将压缩包根的全部文件视为自定义文件内容复制到编译目录的 `files/`。

## WebDAV 上传与兜底

### 准备工作

在仓库 Settings → Secrets and variables → Actions 中添加以下 Repository secrets：

| Secret | 说明 |
|--------|------|
| `WEBDAV_URL` | WebDAV 服务地址，例如 `https://dav.example.com` |
| `WEBDAV_USERNAME` | WebDAV 用户名 |
| `WEBDAV_PASSWORD` | WebDAV 密码 |
| `FILES_ZIP_URL` | （可选）默认的 `files.zip` 下载地址，手动触发时可覆盖 |

### 失败兜底

GitHub Actions artifact 总是在 WebDAV 上传之前完成。如果 WebDAV 上传失败：
- Artifact 不会受影响，你仍可从 Actions 运行页面的 **Artifacts** 区域下载完整固件。
- Workflow 摘要中会出现 `WebDAV upload failed` 提醒及 artifact 名称。
- 日志中会以 warning 形式明确提示兜底方案。

## 产物说明

`firmware-output/` 中包含：
- 经筛选的正式固件
- `firmware-list.txt` —— 固件文件名及大小清单
- `build.config` —— 编译使用的 `.config` 备份，便于复现
- `build-info.txt` —— 源码、分支、目标、编译时间等元信息

## Windows 编辑注意事项

本项目工作流运行在 Ubuntu 22.04（GitHub Actions），所有脚本、`config.yaml`、`applist` 必须使用 LF 换行符。如果你在 Windows 上编辑：

- 确保编辑器设置为 `LF`（Line Feed）而非 `CRLF`。
- 仓库已通过 `.gitattributes` 强制 `*.sh`、`*.yml`、`*.yaml`、`applist` 使用 LF。
- 工作流第一步会执行 `dos2unix` 和 `chmod +x` 进行二次保障，但本地编辑时仍应优先保持 LF。

## 使用方法

1. Fork 或上传本仓库到 GitHub。
2. 编辑 `config.yaml` 填写源码和目标平台。
3. 可选：在 `config/` 下放置 `.config` 成品配置文件。
4. 若没有 `.config`，编辑 `applist` 指定需要的额外软件包。
5. 在仓库 Settings 中配置所需 Secrets（WebDAV 或 `FILES_ZIP_URL`）。
6. 打开 Actions，运行 `OpenWrt CI`。
7. 编译完成后从 artifact 或 WebDAV 获取固件。

## 清除缓存

手动运行 `OpenWrt CI` 时，将 `clean_cache` 设为 `true` 可跳过已有缓存并重新编译。

## 故障排查

- 如果日志中出现 `cc -O2 x86 -c -o conf.o conf.c` 或 `cc: error: x86: No such file or directory`，通常是 `TARGET_ARCH` 环境变量污染了 GNU make 的内置编译规则。本项目脚本已通过 `env -u TARGET_ARCH make ...` 规避，新增脚本中不要直接调用裸 `make`。
