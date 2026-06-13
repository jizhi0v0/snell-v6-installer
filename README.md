# Snell v6 Installer

[中文说明](README.zh-CN.md)

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

The automatic resolver only considers downloads available for the current CPU architecture. It also refuses downgrades by default when `/opt/snell/bin/snell-server-v6` already points to a higher version. For multi-server deployments, pin `VERSION` explicitly so every server uses the same Snell build.

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

The installer prompts in both English and Chinese before changing the service. It shows the detected CPU architecture, current installed version when available, target version, download URL, and planned listen address. On first install, it also asks for the listen port and defaults to `7177`.

Install a specific version with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env VERSION=v6.0.0b2 bash
```

Run without an interactive confirmation:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env ASSUME_YES=1 VERSION=v6.0.0b2 bash
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
sudo env VERSION=v6.0.0b2 ./snell-v6.sh
```

Install a specific beta for a specific CPU:

```bash
sudo env VERSION=v6.0.0b2 ARCH=amd64 ./snell-v6.sh
sudo env VERSION=v6.0.0b2 ARCH=i386 ./snell-v6.sh
sudo env VERSION=v6.0.0b2 ARCH=aarch64 ./snell-v6.sh
```

Install a future stable build:

```bash
sudo env VERSION=v6.0.0 ./snell-v6.sh
```

Set a custom first-install port and PSK:

```bash
sudo env PORT=7177 PSK='replace-with-your-own-psk' ./snell-v6.sh
```

Set dual-stack listen explicitly. `CONFIG_OVERWRITE=1` is needed when a config already exists:

```bash
sudo env CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh
```

Prefer IPv4 for DNS results:

```bash
sudo env DNS_IP_PREFERENCE=prefer-ipv4 ./snell-v6.sh
```

Rewrite the config during an upgrade:

```bash
sudo env CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh
```

When `CONFIG_OVERWRITE=1` is used, existing values are preserved unless you explicitly override them. For example, changing `LISTEN` keeps the existing `psk`.
The previous config is backed up before being rewritten.
When the script writes a config, it validates the listen port, checks whether newly selected TCP ports already appear to be listening, and rejects IPv6 listen values if IPv6 appears disabled on the host.

Print the latest detected Snell v6 version:

```bash
./snell-v6.sh latest
```

Print the currently installed version:

```bash
./snell-v6.sh installed
```

Print the CPU architectures available for a version:

```bash
VERSION=v6.0.0b2 ./snell-v6.sh arches
```

Print the resolved download URL:

```bash
./snell-v6.sh download-url
```

Allow an intentional downgrade:

```bash
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 ./snell-v6.sh
```

Skip the confirmation prompt for automation:

```bash
sudo env ASSUME_YES=1 VERSION=v6.0.0b2 ./snell-v6.sh
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
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo env PRESERVE_CONFIG=1 bash
```

## Tests

Run the local regression suite:

```bash
./tests/snell-v6-regression.sh
```

The suite covers version ordering, downgrade refusal, port validation, listen parsing, IPv6 rejection, occupied-port detection, config preservation, failed-config restore, and binary rollback.

## Notes

- The script only manages `ufw` when `ufw` is already installed. It does not enable `ufw`.
- Existing config content is preserved by default. The script may normalize its ownership and mode to `root:snell 640` so the service user can read it.
- Existing configs are not modified during normal updates. `PORT`, `LISTEN`, `PSK`, `DNS_SERVERS`, and similar config values only affect first install or `CONFIG_OVERWRITE=1`.
- When writing a config, ports must be in the `1` to `65535` range. New ports that are already listening are rejected before download or service changes.
- IPv6 listen values such as `[::]:7177` must be explicit via `LISTEN`, and the script rejects them when IPv6 appears disabled locally.
- `CONFIG_OVERWRITE=1` rewrites the config after creating a timestamped backup, preserves unspecified existing values such as `psk`, `dns`, and `egress-interface`, and restores the previous config if the service cannot restart with the rewritten config.
- Existing service files are backed up before replacement.
- If a service restart fails after switching to a new binary, the script attempts to roll the binary symlink back to the previous version.

## Upstream references

- [Snell v6 blog post](https://nssurge.com/blog/snell-v6/)
- [Official Snell release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
