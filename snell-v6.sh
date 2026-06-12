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

VERSION="${VERSION:-auto}"
PORT="${PORT:-7177}"
LISTEN="${LISTEN:-}"
PSK="${PSK:-}"
DNS_IP_PREFERENCE="${DNS_IP_PREFERENCE:-default}"
DNS_SERVERS="${DNS_SERVERS:-}"
EGRESS_INTERFACE="${EGRESS_INTERFACE:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"
MANAGE_FIREWALL="${MANAGE_FIREWALL:-auto}"
CONFIG_OVERWRITE="${CONFIG_OVERWRITE:-0}"

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
  sudo ./snell-v6.sh [apply|latest|arches|download-url|help]

Actions:
  apply         Install or update Snell v6. Default action.
  latest        Print the latest detected Snell v6 version for the current arch.
  arches        Print available CPU architectures for VERSION, or latest v6.
  download-url  Print the resolved download URL for VERSION/current arch.
  help          Show this help.

Environment variables:
  VERSION=auto              Detect the latest v6 release from official release notes.
  VERSION=v6.0.0b2         Install a specific beta build.
  VERSION=v6.0.0           Install a specific stable build.
  ARCH=auto                 Detect CPU arch automatically.
  ARCH=amd64                Override CPU arch. Also accepts x86_64, i386, arm64, aarch64, armv7l.
  PORT=7177                Default listen port for first install only.
  LISTEN=0.0.0.0:7177      Override the generated listen line for first install.
  PSK=...                  Override the generated PSK for first install.
  DNS_IP_PREFERENCE=default
  DNS_SERVERS=1.1.1.1,8.8.8.8
  EGRESS_INTERFACE=eth0
  CONFIG_OVERWRITE=1       Rewrite the config file on update.
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
  sed -n 's#.*snell-server-\(v[0-9][^-/]*\)-linux-.*#\1#p' <<<"${url}"
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
  curl -fsSL "${RELEASE_NOTES_URL}"
}

available_v6_downloads() {
  fetch_release_notes \
    | grep -Eo 'https://dl\.nssurge\.com/snell/snell-server-v6[^[:space:]]*-linux-[[:alnum:]]+\.zip' \
    | sort -u \
    || true
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
  done <<<"${urls}" | sort -u | sort | tail -n 1 | awk -F '\t' '{print $2}'
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

  if curl -fsIL "${url}" >/dev/null 2>&1; then
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

write_config() {
  local created=0
  local final_listen="${LISTEN}"
  local final_psk="${PSK}"
  local tmp

  if [[ -f "${CONFIG_FILE}" && "${CONFIG_OVERWRITE}" != "1" ]]; then
    ensure_config_permissions
    return 0
  fi

  [[ -n "${final_listen}" ]] || final_listen="0.0.0.0:${PORT}"
  [[ -n "${final_psk}" ]] || final_psk="$(random_psk)"

  tmp="$(mktemp)"
  {
    printf '[snell-server]\n'
    printf 'listen = %s\n' "${final_listen}"
    printf 'psk = %s\n' "${final_psk}"
    printf 'dns-ip-preference = %s\n' "${DNS_IP_PREFERENCE}"
    if [[ -n "${DNS_SERVERS}" ]]; then
      printf 'dns = %s\n' "${DNS_SERVERS}"
    fi
    if [[ -n "${EGRESS_INTERFACE}" ]]; then
      printf 'egress-interface = %s\n' "${EGRESS_INTERFACE}"
    fi
  } >"${tmp}"

  install -d -m 755 "${CONF_DIR}"
  install -m 640 -o root -g "${RUN_GROUP}" "${tmp}" "${CONFIG_FILE}"
  rm -f "${tmp}"
  created=1

  if [[ "${created}" -eq 1 ]]; then
    log "config written to ${CONFIG_FILE}"
    log "psk: ${final_psk}"
  fi
}

write_service_file() {
  local tmp backup=""

  tmp="$(mktemp)"
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
  rm -f "${tmp}"
}

download_and_install_release() {
  local url="$1"
  local version="$2"
  local tmpdir release_path

  tmpdir="$(mktemp -d)"
  release_path="${RELEASES_DIR}/snell-server-${version}"

  (
    trap 'rm -rf -- "$tmpdir"' EXIT

    log "downloading ${url}"
    curl -fsSL -o "${tmpdir}/snell.zip" "${url}"
    unzip -oq "${tmpdir}/snell.zip" -d "${tmpdir}"

    [[ -f "${tmpdir}/snell-server" ]] || die "downloaded archive did not contain snell-server"

    install -d -m 755 "${RELEASES_DIR}" "${BIN_DIR}" "${CONF_DIR}"
    install -m 755 "${tmpdir}/snell-server" "${release_path}"
    validate_release_binary "${release_path}"
    ln -sfn "${release_path}" "${CURRENT_BIN}"
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

  if [[ -n "${LISTEN}" ]]; then
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
  local url version

  need_root
  need_linux
  need_systemd
  install_deps

  url="$(resolve_download_url)"
  version="$(resolve_version "${url}")"
  ensure_download_available "${url}" "${version}"

  ensure_service_user
  download_and_install_release "${url}" "${version}"
  write_config
  write_service_file
  maybe_manage_firewall
  restart_service
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
