# Snell v6 Installer

This repository contains a single script for first-time Snell v6 deployment and later upgrades on a Linux VPS with `systemd`.

It keeps the runtime path stable at `/opt/snell/bin/snell-server-v6`, while storing real binaries under `/opt/snell/releases/`. That gives you easy upgrades and easy rollbacks without overwriting the old binary in place.

## What it does

- First install:
  - downloads the requested Snell v6 build
  - creates `/opt/snell/releases`, `/opt/snell/bin`, and `/opt/snell/conf`
  - creates `/opt/snell/conf/snell-server-v6.conf` when missing
  - creates a `snell-v6` systemd service
  - starts the service
- Later updates:
  - downloads a new build into `/opt/snell/releases`
  - repoints `/opt/snell/bin/snell-server-v6`
  - keeps the existing config by default
  - restarts `snell-v6`

## Version handling

The script supports both beta and stable Snell v6 naming:

- `VERSION=v6.0.0b2`
- `VERSION=v6.0.0`

If `VERSION` is omitted, the script fetches the official Snell release notes and resolves the latest available `v6` build for the current CPU architecture.

## CPU architecture

The script detects the current CPU automatically. You can also override it with `ARCH`:

- `ARCH=amd64` for x86_64 VPS hosts
- `ARCH=i386` for 32-bit x86 hosts
- `ARCH=aarch64` for ARM64 hosts

Common aliases also work: `x86_64`, `i686`, and `arm64`.

For Snell `v6.0.0b2`, the official downloads are:

```text
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-i386.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b2-linux-aarch64.zip
```

## Requirements

- Linux VPS
- `systemd`
- `glibc`
- root or `sudo`

The script can auto-install `curl` and `unzip` on `apt`, `dnf`, and `yum` systems.

## Quick start

Install or update with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo bash
```

Install a specific version with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo VERSION=v6.0.0b2 bash
```

If you are running from a cloned repo:

```bash
chmod +x ./snell-v6.sh
sudo ./snell-v6.sh
```

## Common examples

Install the latest detected v6 build:

```bash
sudo ./snell-v6.sh
```

Install a specific beta:

```bash
sudo VERSION=v6.0.0b2 ./snell-v6.sh
```

Install a specific beta for a specific CPU:

```bash
sudo VERSION=v6.0.0b2 ARCH=amd64 ./snell-v6.sh
sudo VERSION=v6.0.0b2 ARCH=i386 ./snell-v6.sh
sudo VERSION=v6.0.0b2 ARCH=aarch64 ./snell-v6.sh
```

Install a future stable build:

```bash
sudo VERSION=v6.0.0 ./snell-v6.sh
```

Set a custom first-install port and PSK:

```bash
sudo PORT=7177 PSK='replace-with-your-own-psk' ./snell-v6.sh
```

Set dual-stack listen explicitly:

```bash
sudo LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh
```

Prefer IPv4 for DNS results:

```bash
sudo DNS_IP_PREFERENCE=prefer-ipv4 ./snell-v6.sh
```

Rewrite the config during an upgrade:

```bash
sudo CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh
```

Print the latest detected Snell v6 version:

```bash
./snell-v6.sh latest
```

Print the CPU architectures available for a version:

```bash
VERSION=v6.0.0b2 ./snell-v6.sh arches
```

Print the resolved download URL:

```bash
./snell-v6.sh download-url
```

## Installed paths

- Binary symlink: `/opt/snell/bin/snell-server-v6`
- Versioned binaries: `/opt/snell/releases/snell-server-v6.*`
- Config: `/opt/snell/conf/snell-server-v6.conf`
- Service: `/etc/systemd/system/snell-v6.service`

## Rollback

To roll back manually, repoint the symlink to an older binary and restart the service:

```bash
sudo ln -sfn /opt/snell/releases/snell-server-v6.0.0b2 /opt/snell/bin/snell-server-v6
sudo systemctl restart snell-v6
```

## Uninstall

Uninstall with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash
```

Keep `/opt/snell` while removing the service:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo PRESERVE_CONFIG=1 bash
```

## Notes

- The script only manages `ufw` when `ufw` is already installed. It does not enable `ufw`.
- Existing config is preserved unless `CONFIG_OVERWRITE=1`.
- Existing service files are backed up before replacement.

## Upstream references

- [Snell v6 blog post](https://nssurge.com/blog/snell-v6/)
- [Official Snell release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
