# Snell v6 安装器

[English](README.md)

## 关于

用于 `systemd` Linux VPS 的 Snell v6 一键安装、更新和卸载脚本。默认保留已有配置，并保存版本化二进制，方便安全升级和回滚。

这个仓库提供一套用于 Linux VPS 的 Snell v6 安装、更新和卸载脚本，适用于使用 `systemd` 的系统。

脚本会把运行入口固定为 `/opt/snell/bin/snell-server-v6`，真实二进制按版本保存在 `/opt/snell/releases/`。这样后续升级只需要切换软链接，旧版本仍然保留，回滚会比较简单。

## 功能

首次安装会：

- 下载指定的 Snell v6 版本
- 创建 `/opt/snell/releases`、`/opt/snell/bin`、`/opt/snell/conf`
- 在不存在配置时创建 `/opt/snell/conf/snell-server-v6.conf`
- 创建 `snell-v6` systemd 服务
- 启动并设置开机自启

后续更新会：

- 下载新版本到 `/opt/snell/releases`
- 更新 `/opt/snell/bin/snell-server-v6` 软链接
- 默认保留现有配置和 PSK
- 重启 `snell-v6` 服务

## 一键安装或更新

默认自动识别 CPU 架构，并安装官方 release notes 中最新的 Snell v6：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo bash
```

安装器会在修改服务前进行中英双语确认，并显示检测到的 CPU 架构、当前已安装版本、目标版本、下载 URL、计划监听地址和 Snell 模式。如果当前版本解析不到，会显示 `unknown / 未知`。首次安装 `v6.0.0b3+` 时还会用中英双语询问监听端口和模式，端口默认是 `7177`，模式默认是 `default`。

指定安装 `v6.0.0b3`：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env VERSION=v6.0.0b3 bash
```

无人值守执行时：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env ASSUME_YES=1 VERSION=v6.0.0b3 bash
```

## 版本

脚本兼容 beta 和正式版命名：

- `VERSION=v6.0.0b3`
- `VERSION=v6.0.0`

如果不指定 `VERSION`，脚本会从官方 Snell release notes 中自动解析当前 CPU 架构可用的最新 `v6` 版本。

自动解析只会考虑当前 CPU 架构可下载的包。如果 `/opt/snell/bin/snell-server-v6` 已经指向更高版本，脚本默认会拒绝降级。多台服务器批量部署时，建议显式指定 `VERSION`，确保所有服务器使用同一个 Snell 构建。

脚本不是只为某一个 beta 写死的。只要官方包沿用当前下载命名规则，并且当前 CPU 架构有对应包，就支持 Snell v6 的 `v6.0.0b1`、`v6.0.0b2`、`v6.0.0b3`、后续 beta，以及后续正式版，例如 `v6.0.0`。

常见升级路径都使用同一个一键安装脚本：

- 从任意旧 Snell v6 beta 升级到当前自动解析到的最新 beta 或正式版：直接运行默认一键命令。
- 固定安装某个 beta 或正式版：显式设置 `VERSION=...`。
- 有意降级到旧版本：设置 `ALLOW_DOWNGRADE=1`；如果旧版本不支持当前配置里的某个配置项，再配合 `CONFIG_OVERWRITE=1` 让脚本安全重写配置。

## CPU 架构

默认会自动读取当前机器架构。也可以用 `ARCH` 手动指定：

- `ARCH=amd64` 适用于 x86_64 VPS
- `ARCH=i386` 适用于 32 位 x86
- `ARCH=aarch64` 适用于 ARM64

常见别名也支持：`x86_64`、`i686`、`arm64`。

Snell `v6.0.0b3` 官方目前提供这些包：

```text
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-i386.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-aarch64.zip
```

查看某个版本有哪些 CPU 包：

```bash
VERSION=v6.0.0b3 ./snell-v6.sh arches
```

## Snell 模式

Snell `v6.0.0b3` 新增了服务器模式。脚本支持通过 `MODE` 设置：

- `MODE=default`：默认模式，启用流量混淆和 AES 加密。
- `MODE=unshaped`：禁用混淆，仅使用 AES 加密。相比默认模式，吞吐量性能可提高约 10%。
- `MODE=unsafe-raw`：禁用加密和混淆，明文转发所有流量。只应在可信内网或另一个安全隧道下使用。

服务端和客户端模式必须一致。`MODE` 只支持 Snell `v6.0.0b3+`。首次安装 `v6.0.0b3+` 时脚本会交互式询问模式；无人值守或直接回车时默认写入 `mode = default`。从旧配置升级到 `v6.0.0b3+` 时，脚本会先备份配置，再显式补写 `mode = default`，因为 `mode` 是 `v6.0.0b3` 新增配置项。如果要在已安装服务上改成非默认模式，需要使用 `CONFIG_OVERWRITE=1 MODE=...`。

Snell `v6.0.0b3` 所需客户端版本：

- Surge iOS：`5.102.0 (3731)` 或更新版本
- Surge macOS：`6.7.0-11380` 或更新版本

## 默认配置

默认配置文件位置：

```bash
/opt/snell/conf/snell-server-v6.conf
```

首次安装默认内容类似：

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = 随机生成的32位十六进制字符串
mode = default
dns-ip-preference = default
```

对应 Surge 配置示例：

```ini
Snell-V6 = snell, 你的IP或域名, 7177, psk=配置文件里的PSK, version=6
```

查看当前配置：

```bash
sudo cat /opt/snell/conf/snell-server-v6.conf
```

## 配置演进

下面示例是本脚本写入的默认配置，不是 Snell 支持的全部参数列表。脚本重写配置时会保留未知配置行和手动添加的配置项。

<details>
<summary><code>v6.0.0b3</code> 及更新版本</summary>

默认配置：

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = 随机生成的32位十六进制字符串
mode = default
dns-ip-preference = default
```

新增配置项：

- `mode`：`v6.0.0b3` 新增。可选值为 `default`、`unshaped`、`unsafe-raw`。

升级行为：

- 从旧配置升级到 `v6.0.0b3+` 时，脚本会备份配置并显式补写 `mode = default`。
- 如果要使用非默认模式，需要 `CONFIG_OVERWRITE=1 MODE=...`。

</details>

<details>
<summary><code>v6.0.0b2</code></summary>

默认配置：

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = 随机生成的32位十六进制字符串
dns-ip-preference = default
```

相关配置行为：

- `v6.0.0b3` 之前不支持 `mode`。
- Snell v6 增加了 IPv4/IPv6 网络栈控制，例如 `dns-ip-preference` 和多地址 `listen`。

</details>

<details>
<summary><code>v6.0.0b1</code> 或其他固定安装的 pre-b3 构建</summary>

脚本写入的默认配置按 pre-`mode` 布局处理：

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = 随机生成的32位十六进制字符串
dns-ip-preference = default
```

说明：

- 当前官方 release notes 没有单独列出 `v6.0.0b1` 条目。
- 除非你明确要固定旧包做测试，否则建议使用 `v6.0.0b2+`。

</details>

## 常用命令

安装指定 beta：

```bash
sudo env VERSION=v6.0.0b3 ./snell-v6.sh
```

安装未来正式版：

```bash
sudo env VERSION=v6.0.0 ./snell-v6.sh
```

指定端口和 PSK，仅首次创建配置或 `CONFIG_OVERWRITE=1` 时生效：

```bash
sudo env PORT=7177 PSK='replace-with-your-own-psk' ./snell-v6.sh
```

开启 IPv4 + IPv6 双栈监听：

```bash
sudo env CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh
```

首次安装时指定 Snell `v6.0.0b3+` 模式：

```bash
sudo env VERSION=v6.0.0b3 MODE=unshaped ./snell-v6.sh
```

已安装服务需要通过重写配置来修改模式：

```bash
sudo env CONFIG_OVERWRITE=1 MODE=unshaped ./snell-v6.sh
```

`unsafe-raw` 会明文转发流量，只应在可信内网或另一个安全隧道下使用：

```bash
sudo env CONFIG_OVERWRITE=1 MODE=unsafe-raw ./snell-v6.sh
```

使用 `CONFIG_OVERWRITE=1` 时，脚本会保留你没有显式覆盖的旧值。比如只修改 `LISTEN`，旧的 `psk` 会继续保留。
重写前会先备份旧配置。
脚本写入配置前会验证端口范围，检查新选择的 TCP 端口是否已经被监听，并在本机 IPv6 不可用时拒绝 IPv6 监听配置。

IPv6 出口不稳定时，优先使用 IPv4 解析结果：

```bash
sudo env DNS_IP_PREFERENCE=prefer-ipv4 ./snell-v6.sh
```

查看当前解析到的最新 Snell v6 版本：

```bash
./snell-v6.sh latest
```

查看当前已安装版本：

```bash
./snell-v6.sh installed
```

查看下载 URL：

```bash
./snell-v6.sh download-url
```

有意降级时：

```bash
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 ./snell-v6.sh
```

从 `v6.0.0b3+` 降级到不支持 `mode` 的版本：

```bash
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 CONFIG_OVERWRITE=1 ./snell-v6.sh
```

这会先备份配置，再重写配置并移除旧版本不支持的 `mode` 行。如果不加 `CONFIG_OVERWRITE=1`，脚本会拒绝让 `v6.0.0b2` 或更旧版本继续使用包含 `mode` 的配置。

跳过交互确认：

```bash
sudo env ASSUME_YES=1 VERSION=v6.0.0b3 ./snell-v6.sh
```

## 卸载

彻底卸载服务、二进制、配置和运行用户：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash
```

只卸载服务，保留 `/opt/snell` 下的配置和版本文件：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo env PRESERVE_CONFIG=1 bash
```

## 测试

运行本地回归测试：

```bash
./tests/snell-v6-regression.sh
```

测试覆盖版本排序、拒绝误降级、端口校验、监听地址解析、IPv6 不可用时拒绝、端口占用检测、模式校验、`v6.0.0b2` 升级到 `v6.0.0b3` 时迁移 mode、`v6.0.0b3` 降级到 `v6.0.0b2`、配置保留、失败配置恢复和二进制回滚。

## 已安装路径

- 固定二进制入口：`/opt/snell/bin/snell-server-v6`
- 版本化二进制：`/opt/snell/releases/snell-server-v6.*`
- 配置文件：`/opt/snell/conf/snell-server-v6.conf`
- systemd 服务：`/etc/systemd/system/snell-v6.service`

## 回滚

手动回滚到旧版本：

```bash
sudo ln -sfn /opt/snell/releases/snell-server-v6.0.0b2 /opt/snell/bin/snell-server-v6
sudo systemctl restart snell-v6
```

## 说明

- 脚本只会在系统已经安装 `ufw` 时尝试添加或删除端口规则，不会主动启用 `ufw`。
- 已有配置内容默认会保留。脚本可能会把配置权限修正为 `root:snell 640`，让 `snell` 服务用户可以读取。
- 普通更新不会修改已有配置，唯一例外是从旧配置升级到 `v6.0.0b3+` 时会备份配置并补写 `mode = default`。`PORT`、`LISTEN`、`PSK`、`DNS_SERVERS`、`MODE` 等配置参数除此之外只会在首次安装或 `CONFIG_OVERWRITE=1` 时生效。
- `MODE` 只会写入 Snell `v6.0.0b3+` 配置。如果已有配置包含 `mode = ...`，脚本会拒绝安装不支持该配置项的旧目标版本，除非使用 `CONFIG_OVERWRITE=1` 安全移除不兼容配置行。
- 写入配置时，端口必须在 `1` 到 `65535` 范围内。新选择的端口如果已经被监听，脚本会在下载和修改服务前退出。
- IPv6 监听例如 `[::]:7177` 必须通过 `LISTEN` 显式配置；如果脚本检测到本机 IPv6 不可用，会拒绝该配置。
- `CONFIG_OVERWRITE=1` 会先创建带时间戳的配置备份再重写，并保留未显式覆盖的旧值，例如 `psk`、`dns`、`egress-interface`，也会保留脚本不认识的配置行，例如 `shadow-tls`；如果重写后的配置导致服务无法重启，会恢复旧配置。
- 更新 systemd service 文件前，会备份旧文件。
- 如果切换到新二进制后服务重启失败，脚本会尝试把二进制软链接回滚到上一个版本。
- 下载二进制后会先检查能否在当前机器运行，再切换软链接，避免服务指向缺库或架构不匹配的文件。

## 官方资料

- [Snell v6 官方博客](https://nssurge.com/blog/snell-v6/)
- [Snell 官方发布记录](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
