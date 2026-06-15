# Snell v6 Installer

[中文说明](README.zh-CN.md)

## About

One-command Snell v6 installer, updater, and uninstaller for `systemd` Linux VPS hosts. It preserves existing config by default and keeps versioned binaries for safer upgrades and rollbacks.

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

- `VERSION=v6.0.0b3`
- `VERSION=v6.0.0`

If `VERSION` is omitted, the script fetches the official Snell release notes and resolves the latest available `v6` build for the current CPU architecture.

The automatic resolver only considers downloads available for the current CPU architecture. It also refuses downgrades by default when `/opt/snell/bin/snell-server-v6` already points to a higher version. For multi-server deployments, pin `VERSION` explicitly so every server uses the same Snell build.

The script is not tied to a single beta. It supports any official Snell v6 server build that follows the upstream download naming, including `v6.0.0b1`, `v6.0.0b2`, `v6.0.0b3`, later betas, and later stable releases such as `v6.0.0`, as long as the package exists for the selected CPU architecture.

Typical upgrade paths use the same one-command installer:

- Any older Snell v6 beta to the latest detected beta or stable build: run the default one-liner.
- A pinned beta or stable build: set `VERSION=...` explicitly.
- A downgrade to an older build: set `ALLOW_DOWNGRADE=1`, and use `CONFIG_OVERWRITE=1` only when the older build does not support a config key already present in your config.

## CPU architecture

The script detects the current CPU automatically. You can also override it with `ARCH`:

- `ARCH=amd64` for x86_64 VPS hosts
- `ARCH=i386` for 32-bit x86 hosts
- `ARCH=aarch64` for ARM64 hosts

Common aliases also work: `x86_64`, `i686`, and `arm64`.

For Snell `v6.0.0b3`, the official downloads are:

```text
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-i386.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-aarch64.zip
```

## Mode handling

Snell `v6.0.0b3` adds a server mode setting. The script supports these values with `MODE`:

- `MODE=default`: default mode, traffic obfuscation plus AES encryption.
- `MODE=unshaped`: disables obfuscation and keeps AES encryption only. This can improve throughput by about 10% compared with the default mode.
- `MODE=unsafe-raw`: disables both encryption and obfuscation. Traffic is forwarded in plaintext and should only be used inside a trusted private network or another secure tunnel.

The server and client modes must match. `MODE` requires Snell `v6.0.0b3` or newer. On first install with `v6.0.0b3+`, the script asks for the mode interactively and writes `mode = default` when no mode is selected. When updating an older config to `v6.0.0b3+`, the script backs up the config and writes `mode = default` explicitly because `mode` is new in `v6.0.0b3`. To change the mode on an installed server to a non-default value, use `CONFIG_OVERWRITE=1 MODE=...`.

Client versions required for Snell `v6.0.0b3`:

- Surge iOS: `5.102.0 (3731)` or newer
- Surge macOS: `6.7.0-11380` or newer

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

The installer prompts in both English and Chinese before changing the service. It shows the detected CPU architecture, current installed version when available, target version, download URL, planned listen address, and Snell mode. On first install, it also asks for the listen port and mode. The default port is `7177`, and the default mode is `default`.

Install a specific version with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env VERSION=v6.0.0b3 bash
```

Run without an interactive confirmation:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo env ASSUME_YES=1 VERSION=v6.0.0b3 bash
```

If you are running from a cloned repo:

```bash
chmod +x ./snell-v6.sh
sudo ./snell-v6.sh
```

<details>
<summary>Optional: config reference</summary>

Config path:

```bash
/opt/snell/conf/snell-server-v6.conf
```

Current default for `v6.0.0b3+`:

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = randomly generated 32-character hex string
mode = default
dns-ip-preference = default
```

Version notes:

- `v6.0.0b3+`: adds `mode`; this script writes `mode = default` when migrating older configs.
- `v6.0.0b2` and earlier v6 beta configs: no `mode` key.
- Unknown or manually added config lines, such as `shadow-tls`, are preserved during script-managed rewrites.

Surge node example:

```ini
Snell-V6 = snell, your-server-ip-or-domain, 7177, psk=the-psk-from-config, version=6
```

</details>

## Common examples

Install the latest detected v6 build:

```bash
sudo ./snell-v6.sh
```

Install a specific beta:

```bash
sudo env VERSION=v6.0.0b3 ./snell-v6.sh
```

Install a specific beta for a specific CPU:

```bash
sudo env VERSION=v6.0.0b3 ARCH=amd64 ./snell-v6.sh
sudo env VERSION=v6.0.0b3 ARCH=i386 ./snell-v6.sh
sudo env VERSION=v6.0.0b3 ARCH=aarch64 ./snell-v6.sh
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

Set the Snell `v6.0.0b3+` mode on first install:

```bash
sudo env VERSION=v6.0.0b3 MODE=unshaped ./snell-v6.sh
```

Change the mode on an installed server by rewriting the config:

```bash
sudo env CONFIG_OVERWRITE=1 MODE=unshaped ./snell-v6.sh
```

Only use `MODE=unsafe-raw` inside a trusted private network or another secure tunnel:

```bash
sudo env CONFIG_OVERWRITE=1 MODE=unsafe-raw ./snell-v6.sh
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
VERSION=v6.0.0b3 ./snell-v6.sh arches
```

Print the resolved download URL:

```bash
./snell-v6.sh download-url
```

Allow an intentional downgrade:

```bash
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 ./snell-v6.sh
```

Downgrade from `v6.0.0b3+` to a version that does not support `mode`:

```bash
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 CONFIG_OVERWRITE=1 ./snell-v6.sh
```

This backs up the config and rewrites it without the unsupported `mode` line. Without `CONFIG_OVERWRITE=1`, the script refuses to leave a `mode` setting in a config used by `v6.0.0b2` or older.

Skip the confirmation prompt for automation:

```bash
sudo env ASSUME_YES=1 VERSION=v6.0.0b3 ./snell-v6.sh
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

The suite covers version ordering, downgrade refusal, port validation, listen parsing, IPv6 rejection, occupied-port detection, mode validation, `v6.0.0b2` to `v6.0.0b3` mode migration, `v6.0.0b3` to `v6.0.0b2` downgrades, config preservation, failed-config restore, and binary rollback.

## Notes

- The script only manages `ufw` when `ufw` is already installed. It does not enable `ufw`.
- Existing config content is preserved by default. The script may normalize its ownership and mode to `root:snell 640` so the service user can read it.
- Existing configs are not modified during normal updates, except that updating an older config to `v6.0.0b3+` adds `mode = default` with a timestamped backup. `PORT`, `LISTEN`, `PSK`, `DNS_SERVERS`, `MODE`, and similar config values otherwise only affect first install or `CONFIG_OVERWRITE=1`.
- `MODE` is only written for Snell `v6.0.0b3+`. If an existing config contains `mode = ...`, the script refuses to install an older target version unless `CONFIG_OVERWRITE=1` is set so the unsupported line can be removed safely.
- When writing a config, ports must be in the `1` to `65535` range. New ports that are already listening are rejected before download or service changes.
- IPv6 listen values such as `[::]:7177` must be explicit via `LISTEN`, and the script rejects them when IPv6 appears disabled locally.
- `CONFIG_OVERWRITE=1` rewrites the config after creating a timestamped backup, preserves unspecified existing values such as `psk`, `dns`, and `egress-interface`, keeps unrecognized config lines such as `shadow-tls`, and restores the previous config if the service cannot restart with the rewritten config.
- Existing service files are backed up before replacement.
- If a service restart fails after switching to a new binary, the script attempts to roll the binary symlink back to the previous version.

## Upstream references

- [Snell v6 blog post](https://nssurge.com/blog/snell-v6/)
- [Official Snell release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
