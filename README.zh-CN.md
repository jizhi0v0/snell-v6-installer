# Snell v6 安装器

[English](README.md)

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

安装器会在修改服务前进行确认，并显示检测到的 CPU 架构、当前已安装版本、目标版本和下载 URL。如果当前版本解析不到，会显示 `unknown`。

指定安装 `v6.0.0b2`：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env VERSION=v6.0.0b2 bash
```

无人值守执行时：

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env ASSUME_YES=1 VERSION=v6.0.0b2 bash
```

## 版本

脚本兼容 beta 和正式版命名：

- `VERSION=v6.0.0b2`
- `VERSION=v6.0.0`

如果不指定 `VERSION`，脚本会从官方 Snell release notes 中自动解析当前 CPU 架构可用的最新 `v6` 版本。

自动解析只会考虑当前 CPU 架构可下载的包。如果 `/opt/snell/bin/snell-server-v6` 已经指向更高版本，脚本默认会拒绝降级。多台服务器批量部署时，建议显式指定 `VERSION`，确保所有服务器使用同一个 Snell 构建。

## CPU 架构

默认会自动读取当前机器架构。也可以用 `ARCH` 手动指定：

- `ARCH=amd64` 适用于 x86_64 VPS
- `ARCH=i386` 适用于 32 位 x86
- `ARCH=aarch64` 适用于 ARM64

常见别名也支持：`x86_64`、`i686`、`arm64`。

Snell `v6.0.0b2` 官方目前提供这些包：

```text
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-i386.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-aarch64.zip
```

查看某个版本有哪些 CPU 包：

```bash
VERSION=v6.0.0b2 ./snell-v6.sh arches
```

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

## 常用命令

安装指定 beta：

```bash
sudo env VERSION=v6.0.0b2 ./snell-v6.sh
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

跳过交互确认：

```bash
sudo env ASSUME_YES=1 VERSION=v6.0.0b2 ./snell-v6.sh
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
- 已有配置默认会保留，只有设置 `CONFIG_OVERWRITE=1` 才会重写。
- 更新 systemd service 文件前，会备份旧文件。
- 下载二进制后会先检查能否在当前机器运行，再切换软链接，避免服务指向缺库或架构不匹配的文件。

## 官方资料

- [Snell v6 官方博客](https://nssurge.com/blog/snell-v6/)
- [Snell 官方发布记录](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
