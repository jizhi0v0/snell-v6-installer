#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

INSTALL_ROOT="${INSTALL_ROOT:-/opt/snell}"
RELEASES_DIR="${RELEASES_DIR:-${INSTALL_ROOT}/releases}"
BIN_DIR="${BIN_DIR:-${INSTALL_ROOT}/bin}"
CONF_DIR="${CONF_DIR:-${INSTALL_ROOT}/conf}"
CURRENT_BIN="${CURRENT_BIN:-${BIN_DIR}/snell-server-v6}"
CONFIG_FILE="${CONFIG_FILE:-${CONF_DIR}/snell-server-v6.conf}"
SERVICE_NAME="${SERVICE_NAME:-snell-v6}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/${SERVICE_NAME}.service}"
RUN_USER="${RUN_USER:-snell}"
RUN_GROUP="${RUN_GROUP:-snell}"

RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://dl.nssurge.com/snell}"

# Curated list of known Snell v6 builds, space separated, oldest to newest. The
# official release-notes page sometimes lags behind the download server after a
# new beta ships, so these entries let VERSION=auto/latest/arches resolve a
# published build before the notes page lists it. Every candidate is verified
# against the download server before use, so not-yet-published or removed builds
# are ignored. Append new builds here (and in the README) as upstream ships them.
SNELL_V6_KNOWN_VERSIONS="${SNELL_V6_KNOWN_VERSIONS:-v6.0.0b1 v6.0.0b2 v6.0.0b3 v6.0.0b4}"

# CPU arches probed when verifying curated builds against the download server.
SNELL_V6_SUPPORTED_ARCHES="${SNELL_V6_SUPPORTED_ARCHES:-amd64 i386 aarch64 armv7l}"

# Seconds to wait when checking whether a download URL exists.
URL_CHECK_TIMEOUT="${URL_CHECK_TIMEOUT:-15}"

VERSION="${VERSION:-auto}"
PORT_EXPLICIT=0
if [[ -n "${PORT+x}" && -n "${PORT:-}" ]]; then
  PORT_EXPLICIT=1
fi
PORT="${PORT:-7177}"
LISTEN_EXPLICIT=0
if [[ -n "${LISTEN+x}" && -n "${LISTEN:-}" ]]; then
  LISTEN_EXPLICIT=1
fi
LISTEN="${LISTEN:-}"
PSK="${PSK:-}"
DNS_IP_PREFERENCE="${DNS_IP_PREFERENCE:-}"
DNS_SERVERS="${DNS_SERVERS:-}"
EGRESS_INTERFACE="${EGRESS_INTERFACE:-}"
MODE_EXPLICIT=0
if [[ -n "${MODE+x}" && -n "${MODE:-}" ]]; then
  MODE_EXPLICIT=1
fi
MODE="${MODE:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"
MANAGE_FIREWALL="${MANAGE_FIREWALL:-auto}"
CONFIG_OVERWRITE="${CONFIG_OVERWRITE:-0}"
ALLOW_DOWNGRADE="${ALLOW_DOWNGRADE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
CONFIG_BACKUP_PATH=""
TARGET_VERSION="${TARGET_VERSION:-${VERSION}}"

ACTION="${1:-apply}"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./snell-v6.sh [apply|latest|arches|installed|download-url|help]

Actions:
  apply         Install or update Snell v6. Default action.
  latest        Print the latest detected Snell v6 version for the current arch.
  arches        Print available CPU architectures for VERSION, or latest v6.
  installed     Print the currently installed version, if detected.
  download-url  Print the resolved download URL for VERSION/current arch.
  help          Show this help.

Environment variables:
  VERSION=auto              Detect the latest v6 release from official release notes.
  VERSION=v6.0.0b4         Install a specific beta build; b1/b2/b3/b4/future betas are supported when published.
  VERSION=v6.0.0           Install a specific stable build.
  SNELL_V6_KNOWN_VERSIONS   Space-separated curated builds the auto resolver verifies
                            against the download server when the release notes lag.
  ARCH=auto                 Detect CPU arch automatically.
  ARCH=amd64                Override CPU arch. Also accepts x86_64, i386, arm64, aarch64, armv7l.
  PORT=7177                Listen port for first install, or with CONFIG_OVERWRITE=1.
  LISTEN=0.0.0.0:7177      Override the generated listen line when writing config.
  PSK=...                  Override the generated PSK for first install.
  DNS_IP_PREFERENCE=default
  DNS_SERVERS=1.1.1.1,8.8.8.8
  EGRESS_INTERFACE=eth0
  MODE=default             Snell v6.0.0b3+ mode: default, unshaped, or unsafe-raw.
  CONFIG_OVERWRITE=1       Rewrite the config file on update, preserving unspecified values.
  ALLOW_DOWNGRADE=0        Refuse automatic downgrades by default.
  ASSUME_YES=0             Prompt before install/update. Set to 1 for automation.
  MANAGE_FIREWALL=auto     Add an allow rule when ufw exists.
  AUTO_INSTALL_DEPS=1      Install curl/unzip when apt/dnf/yum is available.
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "please run as root or with sudo"
  fi
}

need_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "this script only supports Linux VPS hosts"
}

need_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found; this script expects systemd"
}

normalize_arch() {
  local raw_arch="$1"

  case "${raw_arch}" in
    auto)
      normalize_arch "$(uname -m)"
      ;;
    x86_64|amd64)
      printf 'amd64\n'
      ;;
    aarch64|arm64)
      printf 'aarch64\n'
      ;;
    armv7l|armv7)
      printf 'armv7l\n'
      ;;
    i386|i486|i586|i686)
      printf 'i386\n'
      ;;
    *)
      die "unsupported architecture: ${raw_arch}; supported values are amd64, i386, aarch64, and armv7l"
      ;;
  esac
}

ARCH="$(normalize_arch "${ARCH:-auto}")"

is_truthy() {
  case "${1:-}" in
    1|true|yes|y|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

can_prompt() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

is_valid_port() {
  local port="$1"

  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  [[ "${#port}" -le 5 ]] || return 1
  (( 10#${port} >= 1 && 10#${port} <= 65535 ))
}

validate_port() {
  local port="$1"

  is_valid_port "${port}" || die "invalid port '${port}'; expected an integer from 1 to 65535"
}

normalize_port_value() {
  local port="$1"

  validate_port "${port}"
  printf '%s\n' "$((10#${port}))"
}

trim_value() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"${1:-}"
}

listen_ports() {
  local listen="$1"
  local endpoint port
  local IFS=','
  local -a endpoints

  [[ -n "${listen}" ]] || die "listen value cannot be empty"

  IFS=',' read -r -a endpoints <<<"${listen}"
  for endpoint in "${endpoints[@]}"; do
    endpoint="$(trim_value "${endpoint}")"
    [[ -n "${endpoint}" ]] || die "listen contains an empty endpoint: ${listen}"

    if [[ "${endpoint}" =~ ^\[[^]]+\]:([0-9]+)$ ]]; then
      port="${BASH_REMATCH[1]}"
    elif [[ "${endpoint}" =~ :([0-9]+)$ ]]; then
      port="${BASH_REMATCH[1]}"
    else
      die "invalid listen endpoint '${endpoint}'; expected host:port or [ipv6]:port"
    fi

    validate_port "${port}"
    normalize_port_value "${port}"
  done
}

ipv6_available() {
  local disabled

  [[ -e /proc/net/if_inet6 ]] || return 1
  disabled="$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || printf '1')"
  [[ "${disabled}" != "1" ]]
}

ensure_listen_ipv6_supported() {
  local listen="$1"

  if [[ "${listen}" == *'['*']'* ]] && ! ipv6_available; then
    die "LISTEN includes IPv6, but IPv6 appears disabled on this host; use LISTEN=0.0.0.0:${PORT} or enable IPv6"
  fi
}

validate_listen_value() {
  local listen="$1"

  listen_ports "${listen}" >/dev/null
  ensure_listen_ipv6_supported "${listen}"
}

config_will_be_written() {
  [[ ! -f "${CONFIG_FILE}" ]] || is_truthy "${CONFIG_OVERWRITE}"
}

planned_listen_value() {
  local existing_listen

  if [[ -f "${CONFIG_FILE}" ]] && ! is_truthy "${CONFIG_OVERWRITE}"; then
    existing_listen="$(config_value "listen")"
    if [[ -n "${existing_listen}" ]]; then
      printf '%s\n' "${existing_listen}"
      return 0
    fi
  fi

  if [[ -n "${LISTEN}" ]]; then
    printf '%s\n' "${LISTEN}"
    return 0
  fi

  existing_listen="$(config_value "listen")"
  if [[ -n "${existing_listen}" ]]; then
    printf '%s\n' "${existing_listen}"
    return 0
  fi

  printf '0.0.0.0:%s\n' "${PORT}"
}

is_valid_mode() {
  case "$1" in
    default|unshaped|unsafe-raw)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_mode() {
  local mode="$1"

  is_valid_mode "${mode}" || die "invalid MODE '${mode}'; expected default, unshaped, or unsafe-raw"
}

version_supports_mode() {
  local version="$1"
  local version_key minimum_key

  version_key="$(version_sort_key "${version}")"
  minimum_key="$(version_sort_key "v6.0.0b3")"
  # Sort keys are fixed-width, zero-padded digits and dots, so lexical
  # comparison matches numeric order regardless of locale; this is version >= minimum.
  [[ ! "${version_key}" < "${minimum_key}" ]]
}

mode_default_migration_needed() {
  local target_version="$1"
  local existing_mode

  [[ -f "${CONFIG_FILE}" ]] || return 1
  is_truthy "${CONFIG_OVERWRITE}" && return 1
  version_supports_mode "${target_version}" || return 1

  existing_mode="$(config_value "mode")"
  [[ -z "${existing_mode}" ]]
}

planned_mode_value() {
  local target_version="$1"
  local existing_mode

  version_supports_mode "${target_version}" || return 0

  if [[ -f "${CONFIG_FILE}" ]] && ! is_truthy "${CONFIG_OVERWRITE}"; then
    existing_mode="$(config_value "mode")"
    if [[ -n "${existing_mode}" ]]; then
      printf '%s\n' "${existing_mode}"
      return 0
    fi

    printf 'default\n'
    return 0
  fi

  if [[ -n "${MODE}" ]]; then
    printf '%s\n' "${MODE}"
    return 0
  fi

  existing_mode="$(config_value "mode")"
  if [[ -n "${existing_mode}" ]]; then
    printf '%s\n' "${existing_mode}"
    return 0
  fi

  printf 'default\n'
}

planned_mode_display() {
  local target_version="$1"
  local existing_mode planned_mode

  if ! version_supports_mode "${target_version}"; then
    if [[ -f "${CONFIG_FILE}" ]] && is_truthy "${CONFIG_OVERWRITE}" && [[ -n "$(config_value "mode")" ]]; then
      printf 'removed on config rewrite; target does not support mode / 重写配置时移除；目标版本不支持 mode\n'
      return 0
    fi

    printf 'not written; requires v6.0.0b3+ / 不写入；需要 v6.0.0b3+\n'
    return 0
  fi

  if [[ -f "${CONFIG_FILE}" ]] && ! is_truthy "${CONFIG_OVERWRITE}"; then
    existing_mode="$(config_value "mode")"
    if [[ -n "${existing_mode}" ]]; then
      printf '%s (preserved / 保留)\n' "${existing_mode}"
      return 0
    fi

    printf 'default (new in v6.0.0b3; will be written / v6.0.0b3 新增；将写入)\n'
    return 0
  fi

  planned_mode="$(planned_mode_value "${target_version}")"
  if [[ "${planned_mode}" == "default" && -z "$(config_value "mode")" && -z "${MODE}" ]]; then
    printf 'default (implicit) / 默认（隐式）\n'
    return 0
  fi

  printf '%s\n' "${planned_mode}"
}

prompt_for_config_port() {
  local existing_listen answer default_port

  is_truthy "${ASSUME_YES}" && return 0
  can_prompt || return 0

  existing_listen="$(config_value "listen")"
  default_port="$(normalize_port_value "${PORT}")"

  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    return 0
  fi

  while true; do
    if [[ -f "${CONFIG_FILE}" && -n "${existing_listen}" ]]; then
      printf 'Listen port / 监听端口 [keep current / 保持当前: %s]: ' "${existing_listen}" >&3
    else
      printf 'Listen port / 监听端口 [%s]: ' "${default_port}" >&3
    fi

    IFS= read -r answer <&3 || answer=""
    answer="$(trim_value "${answer}")"

    if [[ -z "${answer}" && -f "${CONFIG_FILE}" && -n "${existing_listen}" ]]; then
      exec 3>&- 3<&-
      return 0
    fi

    if [[ -z "${answer}" ]]; then
      answer="${default_port}"
    fi

    if is_valid_port "${answer}"; then
      PORT="$(normalize_port_value "${answer}")"
      LISTEN="0.0.0.0:${PORT}"
      exec 3>&- 3<&-
      return 0
    fi

    printf 'Invalid port. Please enter an integer from 1 to 65535. / 端口无效，请输入 1 到 65535 之间的整数。\n' >&3
  done
}

prompt_for_config_mode() {
  local target_version="$1"
  local existing_mode answer

  version_supports_mode "${target_version}" || return 0
  is_truthy "${ASSUME_YES}" && return 0
  can_prompt || return 0
  [[ "${MODE_EXPLICIT}" -eq 1 ]] && return 0

  existing_mode="$(config_value "mode")"

  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    return 0
  fi

  {
    printf '\nSnell v6 mode / Snell v6 模式:\n'
    printf '  1. default / 默认：obfuscation + AES / 启用混淆和 AES 加密\n'
    printf '  2. unshaped：AES only / 仅 AES，加密流量看起来完全随机\n'
    printf '  3. unsafe-raw：plaintext / 明文转发，仅限安全内网或安全隧道内\n'
  } >&3

  while true; do
    if [[ -n "${existing_mode}" ]]; then
      printf 'Mode / 模式 [keep current / 保持当前: %s]: ' "${existing_mode}" >&3
    else
      printf 'Mode / 模式 [1, default / 默认]: ' >&3
    fi

    IFS= read -r answer <&3 || answer=""
    answer="$(trim_value "${answer}")"

    if [[ -z "${answer}" && -n "${existing_mode}" ]]; then
      exec 3>&- 3<&-
      return 0
    fi

    case "${answer:-1}" in
      1|default)
        MODE="default"
        ;;
      2|unshaped)
        MODE="unshaped"
        ;;
      3|unsafe-raw)
        MODE="unsafe-raw"
        ;;
      *)
        printf 'Invalid mode. Choose 1/default, 2/unshaped, or 3/unsafe-raw. / 模式无效，请选择 1/default、2/unshaped 或 3/unsafe-raw。\n' >&3
        continue
        ;;
    esac

    exec 3>&- 3<&-
    return 0
  done
}

port_list_contains() {
  local needle="$1"
  local haystack="$2"

  grep -qx -- "${needle}" <<<"${haystack}"
}

service_is_active() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${SERVICE_NAME}"
}

port_is_listening() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn 2>/dev/null \
      | awk -v port="${port}" '{ if ($4 ~ ":" port "$") found=1 } END { exit found ? 0 : 1 }'
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null \
      | awk -v port="${port}" '{ if ($4 ~ ":" port "$") found=1 } END { exit found ? 0 : 1 }'
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  return 1
}

ensure_planned_ports_available() {
  local listen="$1"
  local ports existing_listen existing_ports port service_active=0

  ports="$(listen_ports "${listen}")"
  existing_listen="$(config_value "listen")"
  existing_ports=""
  if [[ -n "${existing_listen}" ]] && ! existing_ports="$(listen_ports "${existing_listen}" 2>/dev/null)"; then
    existing_ports=""
  fi
  if service_is_active; then
    service_active=1
  fi

  while IFS= read -r port; do
    [[ -n "${port}" ]] || continue
    if [[ "${service_active}" -eq 1 ]] && port_list_contains "${port}" "${existing_ports}"; then
      continue
    fi
    if port_is_listening "${port}"; then
      die "tcp/${port} already appears to be listening; choose another PORT or LISTEN"
    fi
  done <<<"${ports}"
}

prepare_config_inputs() {
  local target_version="${1:-${TARGET_VERSION}}"
  local listen existing_mode planned_mode

  [[ -n "${target_version}" ]] || die "target version is required before preparing config"

  existing_mode="$(config_value "mode")"
  if [[ -n "${existing_mode}" ]]; then
    if version_supports_mode "${target_version}"; then
      validate_mode "${existing_mode}"
    elif ! is_truthy "${CONFIG_OVERWRITE}"; then
      die "existing config has mode=${existing_mode}, but ${target_version} does not support mode; downgrade with ALLOW_DOWNGRADE=1 CONFIG_OVERWRITE=1 to rewrite the config without mode, or remove mode manually"
    fi
  fi

  if ! config_will_be_written; then
    if mode_default_migration_needed "${target_version}"; then
      if [[ "${MODE_EXPLICIT}" -eq 1 ]]; then
        validate_mode "${MODE}"
        if [[ "${MODE}" != "default" ]]; then
          die "MODE=${MODE} changes an existing config and requires CONFIG_OVERWRITE=1; automatic v6.0.0b3 migration only writes mode=default"
        fi
      fi
      return 0
    fi

    if [[ "${MODE_EXPLICIT}" -eq 1 ]]; then
      die "MODE only changes an existing config when CONFIG_OVERWRITE=1; current config will otherwise be preserved"
    fi
    return 0
  fi

  if [[ "${LISTEN_EXPLICIT}" -eq 1 ]]; then
    validate_listen_value "${LISTEN}"
  elif [[ "${PORT_EXPLICIT}" -eq 1 ]]; then
    PORT="$(normalize_port_value "${PORT}")"
    LISTEN="0.0.0.0:${PORT}"
  else
    prompt_for_config_port
  fi

  if [[ -z "${LISTEN}" && ! -f "${CONFIG_FILE}" ]]; then
    PORT="$(normalize_port_value "${PORT}")"
    LISTEN="0.0.0.0:${PORT}"
  fi

  listen="$(planned_listen_value)"
  validate_listen_value "${listen}"
  ensure_planned_ports_available "${listen}"

  if [[ "${MODE_EXPLICIT}" -eq 1 ]]; then
    validate_mode "${MODE}"
    if ! version_supports_mode "${target_version}"; then
      die "MODE requires Snell v6.0.0b3 or newer; target version is ${target_version}"
    fi
  fi

  prompt_for_config_mode "${target_version}"
  planned_mode="$(planned_mode_value "${target_version}")"
  if [[ -n "${planned_mode}" ]]; then
    validate_mode "${planned_mode}"
  fi
}

install_deps() {
  local missing=0

  command -v curl >/dev/null 2>&1 || missing=1
  command -v unzip >/dev/null 2>&1 || missing=1

  [[ "${missing}" -eq 1 ]] || return 0
  [[ "${AUTO_INSTALL_DEPS}" == "1" ]] || die "curl and unzip are required"

  if command -v apt-get >/dev/null 2>&1; then
    log "installing curl and unzip via apt-get"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    log "installing curl and unzip via dnf"
    dnf install -y curl unzip
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    log "installing curl and unzip via yum"
    yum install -y curl unzip
    return 0
  fi

  die "unable to install dependencies automatically; please install curl and unzip"
}

extract_version_from_url() {
  local url="$1"
  sed -n \
    -e 's#.*snell-server-\(v[0-9][^-/]*\)-linux-.*#\1#p' \
    -e 's#.*snell-server-\(v[0-9][^-/]*\)$#\1#p' \
    <<<"${url}"
}

version_sort_key() {
  local version="$1"

  if [[ "${version}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)b([0-9]+)$ ]]; then
    printf '%09d.%09d.%09d.%01d.%09d' \
      "${BASH_REMATCH[1]}" \
      "${BASH_REMATCH[2]}" \
      "${BASH_REMATCH[3]}" \
      "0" \
      "${BASH_REMATCH[4]}"
    return 0
  fi

  if [[ "${version}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    printf '%09d.%09d.%09d.%01d.%09d' \
      "${BASH_REMATCH[1]}" \
      "${BASH_REMATCH[2]}" \
      "${BASH_REMATCH[3]}" \
      "1" \
      "0"
    return 0
  fi

  die "unsupported version format: ${version}"
}

fetch_release_notes() {
  curl -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 2 "${RELEASE_NOTES_URL}"
}

remote_url_exists() {
  curl -fsIL -o /dev/null \
    --connect-timeout 15 --max-time "${URL_CHECK_TIMEOUT}" --retry 2 --retry-delay 1 \
    "$1" >/dev/null 2>&1
}

release_notes_v6_downloads() {
  fetch_release_notes \
    | grep -Eo 'https://dl\.nssurge\.com/snell/snell-server-v6[^[:space:]]*-linux-[[:alnum:]]+\.zip' \
    | sort -u \
    || true
}

max_version_key_from_urls() {
  local urls="$1"
  local line version key max=""

  [[ -n "${urls}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    version="$(extract_version_from_url "${line}")"
    [[ -n "${version}" ]] || continue
    key="$(version_sort_key "${version}" 2>/dev/null)" || continue
    if [[ -z "${max}" || "${key}" > "${max}" ]]; then
      max="${key}"
    fi
  done <<<"${urls}"

  printf '%s' "${max}"
}

curated_v6_downloads() {
  local notes_max_key="$1"
  local version key arch url
  local IFS=$' \t\n'

  for version in ${SNELL_V6_KNOWN_VERSIONS}; do
    key="$(version_sort_key "${version}" 2>/dev/null)" || continue
    # Skip builds the release notes already cover; only probe newer ones.
    if [[ -n "${notes_max_key}" ]] && ! [[ "${key}" > "${notes_max_key}" ]]; then
      continue
    fi
    for arch in ${SNELL_V6_SUPPORTED_ARCHES}; do
      url="${DOWNLOAD_BASE_URL}/snell-server-${version}-linux-${arch}.zip"
      if remote_url_exists "${url}"; then
        printf '%s\n' "${url}"
      fi
    done
  done
}

available_v6_downloads() {
  local notes notes_max curated

  if [[ -z "${_AVAILABLE_V6_DOWNLOADS_CACHE+x}" ]]; then
    notes="$(release_notes_v6_downloads)"
    notes_max="$(max_version_key_from_urls "${notes}")"
    curated="$(curated_v6_downloads "${notes_max}")"
    _AVAILABLE_V6_DOWNLOADS_CACHE="$(
      printf '%s\n%s\n' "${notes}" "${curated}" \
        | grep -E '^https://' \
        | sort -u \
        || true
    )"
  fi

  [[ -n "${_AVAILABLE_V6_DOWNLOADS_CACHE}" ]] && printf '%s\n' "${_AVAILABLE_V6_DOWNLOADS_CACHE}"
  return 0
}

extract_arch_from_url() {
  local url="$1"
  sed -n 's#.*-linux-\([[:alnum:]]*\)\.zip#\1#p' <<<"${url}"
}

latest_v6_url() {
  local urls line version key

  urls="$(
    available_v6_downloads \
      | awk -v arch="${ARCH}" '$0 ~ "-linux-" arch "\\.zip$"'
  )"

  [[ -n "${urls}" ]] || die "no Snell v6 download found for arch ${ARCH}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    version="$(extract_version_from_url "${line}")"
    key="$(version_sort_key "${version}")"
    printf '%s\t%s\t%s\n' "${key}" "${version}" "${line}"
  done <<<"${urls}" | sort | tail -n 1 | awk -F '\t' '{print $3}'
}

latest_v6_version() {
  local urls line version key

  urls="$(available_v6_downloads)"
  [[ -n "${urls}" ]] || die "no Snell v6 downloads found in release notes"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    version="$(extract_version_from_url "${line}")"
    key="$(version_sort_key "${version}")"
    printf '%s\t%s\n' "${key}" "${version}"
  done <<<"${urls}" | sort -u | tail -n 1 | awk -F '\t' '{print $2}'
}

available_arches() {
  local version="${VERSION}"
  local arches

  if [[ "${version}" == "auto" ]]; then
    version="$(latest_v6_version)"
  fi

  arches="$(
    available_v6_downloads \
    | awk -v version="${version}" '$0 ~ "snell-server-" version "-linux-" { print }' \
    | while IFS= read -r line; do
        extract_arch_from_url "${line}"
      done \
    | sort -u \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]*$//'
  )"

  [[ -n "${arches}" ]] || die "no downloads found for VERSION=${version}"
  printf '%s: %s\n' "${version}" "${arches}"
}

resolve_download_url() {
  if [[ "${VERSION}" == "auto" ]]; then
    latest_v6_url
    return 0
  fi

  printf '%s/snell-server-%s-linux-%s.zip\n' "${DOWNLOAD_BASE_URL}" "${VERSION}" "${ARCH}"
}

resolve_version() {
  local url="$1"
  extract_version_from_url "${url}"
}

current_installed_version() {
  local resolved=""

  resolved="$(current_installed_path)"

  [[ -n "${resolved}" ]] || return 0
  extract_version_from_url "${resolved}"
}

current_installed_path() {
  if [[ -e "${CURRENT_BIN}" ]]; then
    readlink -f "${CURRENT_BIN}" 2>/dev/null || true
  fi
}

version_relation() {
  local installed_version="$1"
  local target_version="$2"
  local installed_key target_key

  if [[ -z "${installed_version}" ]]; then
    printf 'install\n'
    return 0
  fi

  installed_key="$(version_sort_key "${installed_version}")"
  target_key="$(version_sort_key "${target_version}")"

  if [[ "${target_key}" < "${installed_key}" ]]; then
    printf 'downgrade\n'
  elif [[ "${target_key}" > "${installed_key}" ]]; then
    printf 'update\n'
  else
    printf 'reinstall\n'
  fi
}

ensure_not_downgrade() {
  local target_version="$1"
  local installed_version target_key installed_key

  installed_version="$(current_installed_version)"
  [[ -n "${installed_version}" ]] || return 0

  target_key="$(version_sort_key "${target_version}")"
  installed_key="$(version_sort_key "${installed_version}")"

  if [[ "${target_key}" < "${installed_key}" ]] \
    && ! is_truthy "${ALLOW_DOWNGRADE}"; then
    die "refusing to downgrade from ${installed_version} to ${target_version}; set ALLOW_DOWNGRADE=1 to override"
  fi
}

display_relation() {
  case "$1" in
    install)
      printf 'install / 安装\n'
      ;;
    update)
      printf 'update / 更新\n'
      ;;
    reinstall)
      printf 'reinstall / 重装\n'
      ;;
    downgrade)
      printf 'downgrade / 降级\n'
      ;;
    unknown)
      printf 'unknown / 未知\n'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

confirm_apply() {
  local target_version="$1"
  local url="$2"
  local installed_path installed_version installed_display relation relation_display config_display listen_display mode_display answer

  if is_truthy "${ASSUME_YES}"; then
    return 0
  fi

  installed_path="$(current_installed_path)"
  installed_version="$(current_installed_version)"

  if [[ -n "${installed_version}" ]]; then
    installed_display="${installed_version}"
  elif [[ -n "${installed_path}" ]]; then
    installed_display="unknown / 未知 (${installed_path})"
  else
    installed_display="not installed / 未安装"
  fi

  if [[ -n "${installed_version}" ]]; then
    relation="$(version_relation "${installed_version}" "${target_version}")"
  elif [[ -n "${installed_path}" ]]; then
    relation="unknown"
  else
    relation="install"
  fi
  relation_display="$(display_relation "${relation}")"

  if mode_default_migration_needed "${target_version}"; then
    config_display="add mode=default for v6.0.0b3+, preserving other values / 为 v6.0.0b3+ 补写 mode=default，保留其他值"
  elif [[ -f "${CONFIG_FILE}" ]] && is_truthy "${CONFIG_OVERWRITE}"; then
    config_display="rewrite existing config, preserving unspecified values / 重写已有配置，保留未显式覆盖的值"
  elif [[ -f "${CONFIG_FILE}" ]]; then
    config_display="preserve existing config, normalize permissions / 保留已有配置，仅修正权限"
  else
    config_display="create new config / 创建新配置"
  fi
  listen_display="$(planned_listen_value)"
  mode_display="$(planned_mode_display "${target_version}")"

  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    die "confirmation requires a TTY; set ASSUME_YES=1 for non-interactive use / 确认操作需要 TTY；非交互执行请设置 ASSUME_YES=1"
  fi

  {
    printf '\nSnell v6 install plan / Snell v6 安装计划:\n'
    printf '  Action / 操作: %s\n' "${relation_display}"
    printf '  CPU arch / CPU 架构: %s\n' "${ARCH}"
    printf '  Installed version / 已安装版本: %s\n' "${installed_display}"
    printf '  Target version / 目标版本: %s\n' "${target_version}"
    printf '  Download URL / 下载地址: %s\n' "${url}"
    printf '  Binary symlink / 二进制软链接: %s\n' "${CURRENT_BIN}"
    printf '  Config file / 配置文件: %s\n' "${CONFIG_FILE}"
    printf '  Config action / 配置动作: %s\n' "${config_display}"
    printf '  Listen / 监听地址: %s\n' "${listen_display}"
    printf '  Mode / 模式: %s\n' "${mode_display}"
    printf '  Service / 服务名: %s\n' "${SERVICE_NAME}"
    printf '\nProceed? / 是否继续？[y/N] '
  } >&3

  IFS= read -r answer <&3 || answer=""
  exec 3>&- 3<&-

  if [[ "${answer}" != "y" && "${answer}" != "Y" && "${answer}" != "yes" && "${answer}" != "YES" ]]; then
    die "cancelled by user / 用户已取消"
  fi
}

validate_release_binary() {
  local binary_path="$1"
  local output

  if command -v ldd >/dev/null 2>&1; then
    output="$(ldd "${binary_path}" 2>&1 || true)"
    if grep -q 'not found' <<<"${output}"; then
      printf '%s\n' "${output}" >&2
      die "missing shared libraries for ${binary_path}; try the latest beta/stable build, or install the missing OS packages"
    fi
  fi

  if ! output="$("${binary_path}" --version 2>&1)"; then
    printf '%s\n' "${output}" >&2
    die "downloaded binary cannot run on this host; check VERSION and ARCH"
  fi
}

ensure_download_available() {
  local url="$1"
  local version="$2"

  if remote_url_exists "${url}"; then
    return 0
  fi

  die "download not available for VERSION=${version} ARCH=${ARCH}; run VERSION=${version} ./snell-v6.sh arches"
}

random_psk() {
  od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

ensure_service_user() {
  if ! getent group "${RUN_GROUP}" >/dev/null 2>&1; then
    groupadd -r "${RUN_GROUP}"
  fi

  if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
    useradd -r -g "${RUN_GROUP}" -M -s /usr/sbin/nologin "${RUN_USER}" 2>/dev/null \
      || useradd -r -g "${RUN_GROUP}" -M -s /sbin/nologin "${RUN_USER}"
  fi
}

ensure_config_permissions() {
  [[ -f "${CONFIG_FILE}" ]] || return 0
  chown "root:${RUN_GROUP}" "${CONFIG_FILE}"
  chmod 640 "${CONFIG_FILE}"
}

config_value() {
  local key="$1"

  [[ -f "${CONFIG_FILE}" ]] || return 0
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "${CONFIG_FILE}" | head -n 1
}

backup_config_file() {
  local backup

  [[ -f "${CONFIG_FILE}" ]] || return 0
  backup="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "${CONFIG_FILE}" "${backup}"
  CONFIG_BACKUP_PATH="${backup}"
  log "backed up previous config to ${backup}"
}

write_config() {
  local created=0
  local final_listen="${LISTEN}"
  local final_psk="${PSK}"
  local final_dns_ip_preference="${DNS_IP_PREFERENCE}"
  local final_dns_servers="${DNS_SERVERS}"
  local final_egress_interface="${EGRESS_INTERFACE}"
  local final_mode="${MODE}"
  local existing_listen existing_psk existing_dns_ip_preference existing_dns_servers existing_egress_interface existing_mode
  local include_mode=0 has_dns_servers=0 has_egress_interface=0

  [[ -n "${TARGET_VERSION}" ]] || die "target version is required before writing config"

  if [[ -f "${CONFIG_FILE}" ]] \
    && ! is_truthy "${CONFIG_OVERWRITE}" \
    && ! mode_default_migration_needed "${TARGET_VERSION}"; then
    ensure_config_permissions
    return 0
  fi

  existing_listen="$(config_value "listen")"
  existing_psk="$(config_value "psk")"
  existing_dns_ip_preference="$(config_value "dns-ip-preference")"
  existing_dns_servers="$(config_value "dns")"
  existing_egress_interface="$(config_value "egress-interface")"
  existing_mode="$(config_value "mode")"

  [[ -n "${final_listen}" ]] || final_listen="${existing_listen}"
  [[ -n "${final_listen}" ]] || final_listen="0.0.0.0:${PORT}"
  [[ -n "${final_psk}" ]] || final_psk="${existing_psk}"
  [[ -n "${final_psk}" ]] || final_psk="$(random_psk)"
  [[ -n "${final_dns_ip_preference}" ]] || final_dns_ip_preference="${existing_dns_ip_preference}"
  [[ -n "${final_dns_ip_preference}" ]] || final_dns_ip_preference="default"
  [[ -n "${final_dns_servers}" ]] || final_dns_servers="${existing_dns_servers}"
  [[ -n "${final_egress_interface}" ]] || final_egress_interface="${existing_egress_interface}"
  [[ -n "${final_mode}" ]] || final_mode="${existing_mode}"
  if version_supports_mode "${TARGET_VERSION}"; then
    [[ -n "${final_mode}" ]] || final_mode="default"
    validate_mode "${final_mode}"
    include_mode=1
  fi
  [[ -n "${final_dns_servers}" ]] && has_dns_servers=1
  [[ -n "${final_egress_interface}" ]] && has_egress_interface=1

  install -d -m 755 "${CONF_DIR}"
  backup_config_file

  # Build the config in a subshell so the temp file is removed on any exit,
  # including a set -e abort, while backup_config_file's global state stays
  # in the parent shell for rollback.
  (
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f -- "${tmp}"' EXIT

    if [[ -f "${CONFIG_FILE}" ]]; then
      awk \
        -v listen="${final_listen}" \
        -v psk="${final_psk}" \
        -v mode="${final_mode}" \
        -v include_mode="${include_mode}" \
        -v dns_ip_preference="${final_dns_ip_preference}" \
        -v dns_servers="${final_dns_servers}" \
        -v has_dns_servers="${has_dns_servers}" \
        -v egress_interface="${final_egress_interface}" \
        -v has_egress_interface="${has_egress_interface}" '
          function is_section_header(line) {
            return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/
          }
          function is_snell_server_header(line) {
            return line ~ /^[[:space:]]*\[snell-server\][[:space:]]*$/
          }
          function is_managed_key(line) {
            return line ~ /^[[:space:]]*(listen|psk|mode|dns-ip-preference|dns|egress-interface)[[:space:]]*=/
          }
          function print_managed_keys() {
            print "listen = " listen
            print "psk = " psk
            if (include_mode == 1) {
              print "mode = " mode
            }
            print "dns-ip-preference = " dns_ip_preference
            if (has_dns_servers == 1) {
              print "dns = " dns_servers
            }
            if (has_egress_interface == 1) {
              print "egress-interface = " egress_interface
            }
          }
          is_snell_server_header($0) {
            seen_snell_server = 1
            in_snell_server = 1
            print
            print_managed_keys()
            next
          }
          is_section_header($0) {
            in_snell_server = 0
          }
          in_snell_server && is_managed_key($0) {
            next
          }
          {
            print
          }
          END {
            if (seen_snell_server != 1) {
              print "[snell-server]"
              print_managed_keys()
            }
          }
        ' "${CONFIG_FILE}" >"${tmp}"
    else
      {
        printf '[snell-server]\n'
        printf 'listen = %s\n' "${final_listen}"
        printf 'psk = %s\n' "${final_psk}"
        if [[ "${include_mode}" -eq 1 ]]; then
          printf 'mode = %s\n' "${final_mode}"
        fi
        printf 'dns-ip-preference = %s\n' "${final_dns_ip_preference}"
        if [[ "${has_dns_servers}" -eq 1 ]]; then
          printf 'dns = %s\n' "${final_dns_servers}"
        fi
        if [[ "${has_egress_interface}" -eq 1 ]]; then
          printf 'egress-interface = %s\n' "${final_egress_interface}"
        fi
      } >"${tmp}"
    fi

    install -m 640 -o root -g "${RUN_GROUP}" "${tmp}" "${CONFIG_FILE}"
  )
  created=1

  if [[ "${created}" -eq 1 ]]; then
    log "config written to ${CONFIG_FILE}"
    log "psk: ${final_psk}"
  fi
}

write_service_file() (
  local tmp backup=""

  tmp="$(mktemp)"
  trap 'rm -f -- "${tmp}"' EXIT
  cat >"${tmp}" <<EOF
[Unit]
Description=Snell v6 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
ExecStart=${CURRENT_BIN} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  if [[ -f "${SERVICE_FILE}" ]] && ! cmp -s "${tmp}" "${SERVICE_FILE}"; then
    backup="${SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${SERVICE_FILE}" "${backup}"
    log "backed up previous service file to ${backup}"
  fi

  install -D -m 644 "${tmp}" "${SERVICE_FILE}"
)

download_and_install_release() {
  local url="$1"
  local version="$2"
  local tmpdir release_path

  tmpdir="$(mktemp -d)"
  release_path="${RELEASES_DIR}/snell-server-${version}"

  (
    trap 'rm -rf -- "$tmpdir"' EXIT

    log "downloading ${url}"
    curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 2 -o "${tmpdir}/snell.zip" "${url}"
    unzip -oq "${tmpdir}/snell.zip" -d "${tmpdir}"

    [[ -f "${tmpdir}/snell-server" ]] || die "downloaded archive did not contain snell-server"

    install -d -m 755 "${RELEASES_DIR}" "${BIN_DIR}" "${CONF_DIR}"
    install -m 755 "${tmpdir}/snell-server" "${release_path}"
    validate_release_binary "${release_path}"
    rm -f "${CURRENT_BIN}"
    ln -s "${release_path}" "${CURRENT_BIN}"
  )
}

maybe_manage_firewall() {
  local listen_port
  listen_port="$(configured_port)"

  if [[ "${MANAGE_FIREWALL}" == "0" || "${MANAGE_FIREWALL}" == "false" || "${MANAGE_FIREWALL}" == "no" ]]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1; then
    log "adding ufw allow rule for tcp/${listen_port}"
    ufw allow "${listen_port}/tcp" >/dev/null || true
    return 0
  fi

  if [[ "${MANAGE_FIREWALL}" != "auto" ]]; then
    die "MANAGE_FIREWALL was requested but ufw is not installed"
  fi

  log "ufw not installed; skipping firewall rule management"
}

configured_port() {
  local listen_value=""

  if [[ -f "${CONFIG_FILE}" ]] && ! is_truthy "${CONFIG_OVERWRITE}"; then
    listen_value="$(sed -n 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*//p' "${CONFIG_FILE}" | head -n 1)"
  elif [[ -n "${LISTEN}" ]]; then
    listen_value="${LISTEN}"
  elif [[ -f "${CONFIG_FILE}" ]]; then
    listen_value="$(sed -n 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*//p' "${CONFIG_FILE}" | head -n 1)"
  fi

  if [[ -n "${listen_value}" && "${listen_value}" =~ :([0-9]+)(,|$) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '%s\n' "${PORT}"
}

restart_service() {
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
  systemctl reset-failed "${SERVICE_NAME}" >/dev/null 2>&1 || true

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    systemctl restart "${SERVICE_NAME}"
  else
    systemctl start "${SERVICE_NAME}"
  fi
}

rollback_binary_after_failed_restart() {
  local previous_path="$1"
  local current_path

  current_path="$(current_installed_path)"

  if [[ -z "${previous_path}" || "${previous_path}" == "${current_path}" || ! -x "${previous_path}" ]]; then
    return 1
  fi

  rm -f "${CURRENT_BIN}"
  ln -s "${previous_path}" "${CURRENT_BIN}"
  log "service restart failed; rolled binary symlink back to ${previous_path}"
  systemctl reset-failed "${SERVICE_NAME}" >/dev/null 2>&1 || true
  restart_service >/dev/null 2>&1 || return 1
  return 0
}

restore_config_after_failed_restart() {
  local failed_path

  [[ -n "${CONFIG_BACKUP_PATH}" && -f "${CONFIG_BACKUP_PATH}" ]] || return 1

  failed_path="${CONFIG_FILE}.failed.$(date +%Y%m%d%H%M%S)"
  cp -p "${CONFIG_FILE}" "${failed_path}" 2>/dev/null || true
  install -m 640 -o root -g "${RUN_GROUP}" "${CONFIG_BACKUP_PATH}" "${CONFIG_FILE}"
  log "service restart failed; restored config from ${CONFIG_BACKUP_PATH}"
  if [[ -f "${failed_path}" ]]; then
    log "kept failed config at ${failed_path}"
  fi
  return 0
}

show_summary() {
  local version="$1"
  log "installed version: ${version}"
  log "current binary: $(readlink -f "${CURRENT_BIN}")"
  log "config file: ${CONFIG_FILE}"
  log "service: ${SERVICE_NAME}"
  log "status:"
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
}

apply() {
  local url version previous_path config_restored=0

  need_root
  need_linux
  need_systemd
  install_deps

  url="$(resolve_download_url)"
  version="$(resolve_version "${url}")"
  TARGET_VERSION="${version}"
  ensure_download_available "${url}" "${version}"
  ensure_not_downgrade "${version}"
  prepare_config_inputs "${version}"
  confirm_apply "${version}" "${url}"

  previous_path="$(current_installed_path)"
  ensure_service_user
  download_and_install_release "${url}" "${version}"
  write_config
  write_service_file
  maybe_manage_firewall

  if ! restart_service; then
    if restore_config_after_failed_restart; then
      config_restored=1
      if restart_service; then
        die "service failed after config rewrite; restored the previous config; check journalctl -xeu ${SERVICE_NAME}.service"
      fi
    fi

    if rollback_binary_after_failed_restart "${previous_path}"; then
      if [[ "${config_restored}" -eq 1 ]]; then
        die "service failed after update; restored the previous config and rolled back to the previous binary; check journalctl -xeu ${SERVICE_NAME}.service"
      fi
      die "service failed after update and was rolled back to the previous binary; check journalctl -xeu ${SERVICE_NAME}.service"
    fi
    die "service failed to start; check journalctl -xeu ${SERVICE_NAME}.service"
  fi

  show_summary "${version}"
}

case "${ACTION}" in
  apply)
    apply
    ;;
  latest)
    basename "$(latest_v6_url)" | sed -n 's/^snell-server-\(v6[^-]*\)-linux-.*$/\1/p'
    ;;
  arches)
    available_arches
    ;;
  installed)
    current_installed_version
    ;;
  download-url)
    resolve_download_url
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "unknown action: ${ACTION}"
    ;;
esac
