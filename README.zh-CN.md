# Snell v6 安装器

[English](README.md)

> 用于 `systemd` Linux VPS 的 Snell v6 **一键安装、更新、卸载**脚本。
> 默认保留已有配置，并保存版本化二进制，方便安全升级和秒级回滚。

## 快速开始

一条命令安装或更新到最新版 Snell v6：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo bash
```

就这么简单。脚本会自动识别 CPU、下载最新版本、写入配置、创建并启动 `systemd` 服务。

卸载同样只需一条命令：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash
```

> [!NOTE]
> 修改服务前，安装器会显示中英双语摘要——检测到的 CPU、当前版本、目标版本、下载 URL、监听地址和模式——并等待确认。首次安装时还会询问监听端口（默认 `7177`）和模式（默认 `default`）。

## 为什么用这个脚本

- **安全升级与回滚**——运行入口 `/opt/snell/bin/snell-server-v6` 是软链接，真实二进制按版本保存在 `/opt/snell/releases/`。升级只切换软链接，旧版本始终保留，随时可回滚。
- **保留你的配置**——更新时已有设置（PSK、监听、DNS、`shadow-tls` 等自定义项）原样保留。
- **智能版本解析**——不指定 `VERSION` 时自动找到当前 CPU 可用的最新 v6，并用内置的已知版本清单到下载服务器逐一校验，因此刚发布的 beta（如 `v6.0.0b4`）即使官方 release notes 页面还没收录也能被识别；默认拒绝误降级。
- **面向未来**——支持任何沿用官方命名的 v6 构建，从 `v6.0.0b1` 到未来的正式版（如 `v6.0.0`）。

<details>
<summary>脚本具体做了什么</summary>

**首次安装**
- 下载指定的 Snell v6 版本
- 创建 `/opt/snell/releases`、`/opt/snell/bin`、`/opt/snell/conf`
- 在不存在时写入 `/opt/snell/conf/snell-server-v6.conf`
- 创建并启动 `snell-v6` systemd 服务（含开机自启）

**后续更新**
- 下载新版本到 `/opt/snell/releases`
- 重新指向 `/opt/snell/bin/snell-server-v6` 软链接
- 默认保留现有配置和 PSK
- 重启 `snell-v6` 服务

</details>

## 运行要求

- 带 `systemd` 和 `glibc` 的 Linux VPS
- `root` 或 `sudo`

脚本可在 `apt`、`dnf`、`yum` 系统上自动安装 `curl` 和 `unzip`。

## 配置项

通过环境变量传入，例如 `sudo env VERSION=v6.0.0b4 MODE=unshaped ./snell-v6.sh`。

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `VERSION` | 目标版本，如 `v6.0.0b4` 或 `v6.0.0` | 自动解析最新 v6 |
| `SNELL_V6_KNOWN_VERSIONS` | 自动解析时校验的内置已知版本清单，用于 release notes 落后时兜底 | `v6.0.0b1`…`b4` |
| `ARCH` | 指定 CPU：`amd64`、`i386`、`aarch64`（别名：`x86_64`、`i686`、`arm64`） | 自动识别 |
| `PORT` | 监听端口（仅首次安装生效） | `7177` |
| `PSK` | 预共享密钥（仅首次安装生效） | 随机 32 位十六进制 |
| `MODE` | `default`、`unshaped` 或 `unsafe-raw`——需 `v6.0.0b3+` | `default` |
| `LISTEN` | 完整监听地址，如 `0.0.0.0:7177,[::]:7177` | `0.0.0.0:<PORT>` |
| `DNS_IP_PREFERENCE` | 如 `prefer-ipv4` | `default` |
| `CONFIG_OVERWRITE` | `1` 重写已有配置（保留未指定的旧值） | 关闭 |
| `ALLOW_DOWNGRADE` | `1` 允许安装更旧版本 | 关闭 |
| `ASSUME_YES` | `1` 跳过确认提示（无人值守） | 关闭 |
| `PRESERVE_CONFIG` | `1` 卸载时保留 `/opt/snell` | 关闭 |

> [!TIP]
> `PORT`、`PSK`、`LISTEN`、`MODE`、`DNS_*` 只在**首次安装**或设置 `CONFIG_OVERWRITE=1` 时生效。普通更新不会动你的配置。

### 子命令

只读、不修改任何内容：

```bash
./snell-v6.sh latest                       # 解析到的最新 v6 版本
./snell-v6.sh installed                     # 当前已安装版本
./snell-v6.sh download-url                  # 解析后的下载 URL
VERSION=v6.0.0b4 ./snell-v6.sh arches       # 某版本提供的 CPU 包
```

> [!NOTE]
> `VERSION=auto`、`latest`、`arches` 会从官方 release notes **和**内置已知版本清单（`SNELL_V6_KNOWN_VERSIONS`）两处解析，并逐一到下载服务器校验。因此即使 release notes 页面还落后，刚发布的版本（如 `v6.0.0b4`）也能被识别。如果上游发布的版本比两处来源都新，请显式指定 `VERSION`（并把它加入 `SNELL_V6_KNOWN_VERSIONS`）。

## 服务模式

Snell `v6.0.0b3+` 新增了服务器模式（用 `MODE` 设置）。服务端和客户端模式**必须一致**。

| 模式 | 加密 | 混淆 | 说明 |
| --- | --- | --- | --- |
| `default` | ✅ AES | ✅ | 推荐 |
| `unshaped` | ✅ AES | ❌ | 吞吐量约提升 10% |
| `unsafe-raw` | ❌ | ❌ | 明文转发——见下方警告 |

> [!WARNING]
> `unsafe-raw` 会明文转发流量。只应在可信内网或另一个安全隧道下使用。

首次安装 `v6.0.0b3+` 时脚本会交互式询问模式（默认 `default`）。从旧配置升级到 `v6.0.0b3+` 时会先备份配置，再显式写入 `mode = default`。要修改已安装服务的模式，使用 `CONFIG_OVERWRITE=1 MODE=...`。

`mode` 需要支持 Snell v6 的 Surge 客户端。各 Snell 版本所需的最低客户端版本，请查阅[官方发布记录](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)。

<details>
<summary>配置文件参考</summary>

配置文件位置：`/opt/snell/conf/snell-server-v6.conf`

`v6.0.0b3+` 默认配置：

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = 随机生成的32位十六进制字符串
mode = default
dns-ip-preference = default
```

- `v6.0.0b3+` 新增 `mode`；更早的 v6 beta（`v6.0.0b2` 及之前）没有 `mode`。
- 脚本重写配置时会保留未知或手动添加的行，例如 `shadow-tls`。

对应 Surge 配置示例：

```ini
Snell-V6 = snell, 你的IP或域名, 7177, psk=配置文件里的PSK, version=6
```

</details>

## 常用示例

```bash
# 安装指定 beta
sudo env VERSION=v6.0.0b4 ./snell-v6.sh

# 为指定 CPU 安装
sudo env VERSION=v6.0.0b4 ARCH=aarch64 ./snell-v6.sh

# 首次安装指定端口和 PSK
sudo env PORT=7177 PSK='replace-with-your-own-psk' ./snell-v6.sh

# 开启 IPv4 + IPv6 双栈监听（重写已有配置）
sudo env CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh

# DNS 优先使用 IPv4 结果
sudo env DNS_IP_PREFERENCE=prefer-ipv4 ./snell-v6.sh

# 修改已安装服务的模式
sudo env CONFIG_OVERWRITE=1 MODE=unshaped ./snell-v6.sh

# 无人值守安装（无提示）
sudo env ASSUME_YES=1 VERSION=v6.0.0b4 ./snell-v6.sh

# 有意降级
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 ./snell-v6.sh
```

> [!NOTE]
> 从 `v6.0.0b3+` 降级到不支持 `mode` 的版本时还需加 `CONFIG_OVERWRITE=1`，以安全移除不兼容的 `mode` 行：
> `sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 CONFIG_OVERWRITE=1 ./snell-v6.sh`

从克隆的仓库运行？先 `chmod +x ./snell-v6.sh`，再 `sudo ./snell-v6.sh`。

## 已安装路径

| | 路径 |
| --- | --- |
| 二进制软链接 | `/opt/snell/bin/snell-server-v6` |
| 版本化二进制 | `/opt/snell/releases/snell-server-v6.*` |
| 配置文件 | `/opt/snell/conf/snell-server-v6.conf` |
| systemd 服务 | `/etc/systemd/system/snell-v6.service` |

## 回滚

把软链接指回旧二进制并重启：

```bash
sudo ln -sfn /opt/snell/releases/snell-server-v6.0.0b2 /opt/snell/bin/snell-server-v6
sudo systemctl restart snell-v6
```

## 卸载

```bash
# 彻底卸载（服务、二进制、配置、运行用户）
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash

# 只卸载服务，保留 /opt/snell
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo env PRESERVE_CONFIG=1 bash
```

## 安全保障

脚本在设计上偏保守：

- **默认保留配置**，可能会把权限修正为 `root:snell 640`，让 `snell` 服务用户可读。
- **重写前先备份**——`CONFIG_OVERWRITE=1` 和替换 service 文件前都会创建带时间戳的备份。若重写后服务无法重启，会恢复旧配置。
- **写入前校验**——监听端口必须在 `1`–`65535`；已被监听的端口在下载和修改服务前就会被拒绝；本机 IPv6 不可用时拒绝 IPv6 监听配置。
- **二进制回滚**——切换新二进制后服务重启失败时，软链接会回滚到上一个版本。
- **`ufw`** 只在系统已安装时才处理，脚本从不主动启用它。

## 测试

```bash
./tests/snell-v6-regression.sh
```

覆盖版本排序、拒绝误降级、端口校验、监听解析、IPv6 拒绝、端口占用检测、模式校验、`v6.0.0b2`↔`v6.0.0b3` 迁移、配置保留、失败配置恢复和二进制回滚。

## 官方资料

- [Snell v6 官方博客](https://nssurge.com/blog/snell-v6/)
- [Snell 官方发布记录](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
