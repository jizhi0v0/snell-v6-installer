# Snell v6 Installer

[中文说明](README.zh-CN.md)

> One-command **install, update, and uninstall** for Snell v6 on `systemd` Linux VPS hosts.
> Keeps your existing config, and stores versioned binaries for safe upgrades and instant rollbacks.

## Quick start

Install or update to the latest Snell v6 with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6.sh | sudo bash
```

That's it. The script auto-detects your CPU, downloads the latest build, writes a config, creates a `systemd` service, and starts it.

Uninstall just as easily:

```bash
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash
```

> [!NOTE]
> Before changing anything, the installer shows a bilingual (English / 中文) summary — detected CPU, current version, target version, download URL, listen address, and mode — and waits for confirmation. On first install it also asks for the listen port (default `7177`) and mode (default `default`).

## Why this script

- **Safe upgrades & rollbacks** — the runtime path `/opt/snell/bin/snell-server-v6` is a symlink; real binaries live under `/opt/snell/releases/`. Upgrades just repoint the symlink, so the old binary is always there to roll back to.
- **Your config is preserved** — existing settings (PSK, listen, DNS, custom keys like `shadow-tls`) survive updates untouched.
- **Smart version resolution** — omit `VERSION` and it finds the latest v6 build for your CPU, cross-checking a built-in list of known builds against the download server so a freshly published beta (like `v6.0.0b4`) is picked up even before the official release-notes page lists it; refuses accidental downgrades by default.
- **Future-proof** — works with any official v6 build that follows upstream naming, from `v6.0.0b1` through future stable releases like `v6.0.0`.

<details>
<summary>What it does, step by step</summary>

**First install**
- Downloads the requested Snell v6 build
- Creates `/opt/snell/releases`, `/opt/snell/bin`, and `/opt/snell/conf`
- Writes `/opt/snell/conf/snell-server-v6.conf` (if missing)
- Creates and starts the `snell-v6` systemd service

**Later updates**
- Downloads the new build into `/opt/snell/releases`
- Repoints the `/opt/snell/bin/snell-server-v6` symlink
- Keeps the existing config by default
- Restarts `snell-v6`

</details>

## Requirements

- Linux VPS with `systemd` and `glibc`
- `root` or `sudo`

The script can auto-install `curl` and `unzip` on `apt`, `dnf`, and `yum` systems.

## Configuration

Pass options as environment variables, e.g. `sudo env VERSION=v6.0.0b4 MODE=unshaped ./snell-v6.sh`.

| Variable | What it does | Default |
| --- | --- | --- |
| `VERSION` | Target build, e.g. `v6.0.0b4` or `v6.0.0` | latest detected v6 |
| `SNELL_V6_KNOWN_VERSIONS` | Curated builds the auto-resolver verifies when the release notes lag | `v6.0.0b1`…`b4` |
| `ARCH` | CPU override: `amd64`, `i386`, `aarch64` (aliases: `x86_64`, `i686`, `arm64`) | auto-detect |
| `PORT` | Listen port (first install only) | `7177` |
| `PSK` | Pre-shared key (first install only) | random 32-char hex |
| `MODE` | `default`, `unshaped`, or `unsafe-raw` — requires `v6.0.0b3+` | `default` |
| `LISTEN` | Full listen address, e.g. `0.0.0.0:7177,[::]:7177` | `0.0.0.0:<PORT>` |
| `DNS_IP_PREFERENCE` | e.g. `prefer-ipv4` | `default` |
| `CONFIG_OVERWRITE` | `1` rewrites an existing config (keeps unspecified values) | off |
| `ALLOW_DOWNGRADE` | `1` permits installing an older version | off |
| `ASSUME_YES` | `1` skips the confirmation prompt (for automation) | off |
| `PRESERVE_CONFIG` | `1` keeps `/opt/snell` when uninstalling | off |

> [!TIP]
> `PORT`, `PSK`, `LISTEN`, `MODE`, and `DNS_*` only take effect on **first install** or when `CONFIG_OVERWRITE=1` is set. Normal updates never touch your config.

### Subcommands

Read-only helpers that don't change anything:

```bash
./snell-v6.sh latest                       # latest detected v6 version
./snell-v6.sh installed                     # currently installed version
./snell-v6.sh download-url                  # resolved download URL
VERSION=v6.0.0b4 ./snell-v6.sh arches       # CPU packages available for a version
```

> [!NOTE]
> `VERSION=auto`, `latest`, and `arches` resolve from the official release notes **and** a curated list of known builds (`SNELL_V6_KNOWN_VERSIONS`), verifying each candidate against the download server. A just-published build such as `v6.0.0b4` is found even while the release-notes page still lags. If upstream ships something newer than both sources, pin `VERSION` explicitly (and add it to `SNELL_V6_KNOWN_VERSIONS`).

## Server modes

Snell `v6.0.0b3+` adds a server mode (set with `MODE`). The server and client modes **must match**.

| Mode | Encryption | Obfuscation | Notes |
| --- | --- | --- | --- |
| `default` | ✅ AES | ✅ | Recommended |
| `unshaped` | ✅ AES | ❌ | ~10% higher throughput |
| `unsafe-raw` | ❌ | ❌ | Plaintext — see warning below |

> [!WARNING]
> `unsafe-raw` forwards traffic in plaintext. Only use it inside a trusted private network or another secure tunnel.

On first install with `v6.0.0b3+`, the script asks for the mode interactively (defaults to `default`). When migrating an older config to `v6.0.0b3+`, it backs up the config and writes `mode = default` explicitly. To change the mode on an installed server, use `CONFIG_OVERWRITE=1 MODE=...`.

`mode` requires a Snell-v6-capable Surge client. For the minimum client build per Snell version, see the [official Snell release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell).

<details>
<summary>Config file reference</summary>

Config path: `/opt/snell/conf/snell-server-v6.conf`

Default for `v6.0.0b3+`:

```ini
[snell-server]
listen = 0.0.0.0:7177
psk = randomly generated 32-character hex string
mode = default
dns-ip-preference = default
```

- `v6.0.0b3+` adds `mode`; older v6 betas (`v6.0.0b2` and earlier) have no `mode` key.
- Unknown or manually added lines, such as `shadow-tls`, are preserved during script-managed rewrites.

Matching Surge node:

```ini
Snell-V6 = snell, your-server-ip-or-domain, 7177, psk=the-psk-from-config, version=6
```

</details>

## Examples

```bash
# Install a specific beta
sudo env VERSION=v6.0.0b4 ./snell-v6.sh

# Install for a specific CPU
sudo env VERSION=v6.0.0b4 ARCH=aarch64 ./snell-v6.sh

# Custom port and PSK on first install
sudo env PORT=7177 PSK='replace-with-your-own-psk' ./snell-v6.sh

# Enable IPv4 + IPv6 dual-stack listen (rewrites an existing config)
sudo env CONFIG_OVERWRITE=1 LISTEN='0.0.0.0:7177,[::]:7177' ./snell-v6.sh

# Prefer IPv4 for DNS results
sudo env DNS_IP_PREFERENCE=prefer-ipv4 ./snell-v6.sh

# Change mode on an installed server
sudo env CONFIG_OVERWRITE=1 MODE=unshaped ./snell-v6.sh

# Unattended install (no prompt)
sudo env ASSUME_YES=1 VERSION=v6.0.0b4 ./snell-v6.sh

# Intentional downgrade
sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 ./snell-v6.sh
```

> [!NOTE]
> Downgrading from `v6.0.0b3+` to a version without `mode` support needs `CONFIG_OVERWRITE=1` too, so the unsupported `mode` line can be removed safely:
> `sudo env VERSION=v6.0.0b2 ALLOW_DOWNGRADE=1 CONFIG_OVERWRITE=1 ./snell-v6.sh`

Running from a cloned repo? Use `chmod +x ./snell-v6.sh` then `sudo ./snell-v6.sh`.

## Installed paths

| | Path |
| --- | --- |
| Binary symlink | `/opt/snell/bin/snell-server-v6` |
| Versioned binaries | `/opt/snell/releases/snell-server-v6.*` |
| Config | `/opt/snell/conf/snell-server-v6.conf` |
| Service | `/etc/systemd/system/snell-v6.service` |

## Rollback

Repoint the symlink to an older binary and restart:

```bash
sudo ln -sfn /opt/snell/releases/snell-server-v6.0.0b2 /opt/snell/bin/snell-server-v6
sudo systemctl restart snell-v6
```

## Uninstall

```bash
# Full uninstall
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo bash

# Remove the service but keep /opt/snell
curl -fsSL https://raw.githubusercontent.com/jizhi0v0/snell-v6-installer/main/snell-v6-uninstall.sh | sudo env PRESERVE_CONFIG=1 bash
```

## Safety guarantees

The script is conservative by design:

- **Configs are preserved** by default; it may normalize ownership/mode to `root:snell 640` so the service can read it.
- **Backups before rewrites** — `CONFIG_OVERWRITE=1` and service-file replacement create timestamped backups first. If the service can't restart with a rewritten config, the previous config is restored.
- **Validated writes** — listen ports must be `1`–`65535`; already-listening ports are rejected before any download or service change; IPv6 listen values are rejected when IPv6 looks disabled on the host.
- **Binary rollback** — if the service fails to restart on a new binary, the symlink is rolled back to the previous version.
- **`ufw`** is only touched when already installed; the script never enables it.

## Tests

```bash
./tests/snell-v6-regression.sh
```

Covers version ordering, downgrade refusal, port validation, listen parsing, IPv6 rejection, occupied-port detection, mode validation, `v6.0.0b2`↔`v6.0.0b3` migration, config preservation, failed-config restore, and binary rollback.

## Upstream references

- [Snell v6 blog post](https://nssurge.com/blog/snell-v6/)
- [Official Snell release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
