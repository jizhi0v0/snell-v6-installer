#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

# Match the installer platform and service scope.
PLATFORM="${PLATFORM:-$(uname -s)}"
case "${PLATFORM}" in
  Linux|linux) PLATFORM=linux ;;
  Darwin|macOS) PLATFORM=macOS ;;
  *) printf 'Unsupported platform: %s\n' "${PLATFORM}" >&2; exit 1 ;;
esac
SERVICE_SCOPE="${SERVICE_SCOPE:-system}"
if [[ "${PLATFORM}" == macOS ]]; then
  SERVICE_LABEL="${SERVICE_LABEL:-com.snell.${SERVICE_NAME:-snell-v6}}"
  if [[ "${SERVICE_SCOPE}" == user ]]; then
    INSTALL_ROOT="${INSTALL_ROOT:-${HOME}/Library/Application Support/snell-v6}"
    SERVICE_FILE="${SERVICE_FILE:-${HOME}/Library/LaunchAgents/${SERVICE_LABEL}.plist}"
    RUN_USER="${RUN_USER:-$(id -un)}"
    RUN_GROUP="${RUN_GROUP:-$(id -gn)}"
    LAUNCH_DOMAIN="gui/$(id -u)"
  else
    SERVICE_FILE="${SERVICE_FILE:-/Library/LaunchDaemons/${SERVICE_LABEL}.plist}"
    RUN_USER="${RUN_USER:-nobody}"
    RUN_GROUP="${RUN_GROUP:-nobody}"
    LAUNCH_DOMAIN=system
  fi
fi
[[ "${SERVICE_SCOPE}" == system || ( "${PLATFORM}" == macOS && "${SERVICE_SCOPE}" == user ) ]] || {
  printf 'SERVICE_SCOPE must be system, or user on macOS\n' >&2; exit 1;
}

INSTALL_ROOT="${INSTALL_ROOT:-/opt/snell}"
CONFIG_FILE="${CONFIG_FILE:-${INSTALL_ROOT}/conf/snell-server-v6.conf}"
SERVICE_NAME="${SERVICE_NAME:-snell-v6}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/${SERVICE_NAME}.service}"
RUN_USER="${RUN_USER:-snell}"
RUN_GROUP="${RUN_GROUP:-snell}"
PORT="${PORT:-}"
PRESERVE_CONFIG="${PRESERVE_CONFIG:-0}"
REMOVE_USER="${REMOVE_USER:-1}"
REMOVE_UFW_RULE="${REMOVE_UFW_RULE:-auto}"

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./snell-v6-uninstall.sh [help]

Environment variables:
  SERVICE_SCOPE=system    macOS: use user to remove a user-level installation.
  PRESERVE_CONFIG=0       Remove /opt/snell by default. Set to 1 to keep it.
  REMOVE_USER=1           Remove snell user/group when possible.
  REMOVE_UFW_RULE=auto    Delete ufw allow rule when ufw exists.
  PORT=7177               Override port detection for ufw cleanup.
EOF
}

need_root() {
  [[ "${PLATFORM}" == macOS && "${SERVICE_SCOPE}" == user && "${EUID}" -ne 0 ]] && return 0
  if [[ "${EUID}" -ne 0 ]]; then
    die "please run as root or with sudo"
  fi
}

configured_port() {
  local listen_value=""

  if [[ -n "${PORT}" ]]; then
    printf '%s\n' "${PORT}"
    return 0
  fi

  if [[ -f "${CONFIG_FILE}" ]]; then
    listen_value="$(sed -n 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*//p' "${CONFIG_FILE}" | head -n 1)"
  fi

  if [[ -n "${listen_value}" && "${listen_value}" =~ :([0-9]+)(,|$) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '7177\n'
}

remove_service() {
  if [[ "${PLATFORM}" == macOS ]]; then
    if launchctl print "${LAUNCH_DOMAIN}/${SERVICE_LABEL}" >/dev/null 2>&1; then
      launchctl bootout "${LAUNCH_DOMAIN}/${SERVICE_LABEL}"
    fi
    rm -f "${SERVICE_FILE}" "${SERVICE_FILE}".bak.*
    log "removed launchd service ${SERVICE_LABEL}"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  rm -f "${SERVICE_FILE}" "${SERVICE_FILE}".bak.*

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  log "removed systemd service ${SERVICE_NAME}"
}

remove_files() {
  if [[ "${PRESERVE_CONFIG}" == "1" || "${PRESERVE_CONFIG}" == "true" || "${PRESERVE_CONFIG}" == "yes" ]]; then
    log "preserved ${INSTALL_ROOT}"
    return 0
  fi

  rm -rf "${INSTALL_ROOT}"
  log "removed ${INSTALL_ROOT}"
}

remove_firewall_rule() {
  [[ "${PLATFORM}" == macOS ]] && return 0
  local port

  if [[ "${REMOVE_UFW_RULE}" == "0" || "${REMOVE_UFW_RULE}" == "false" || "${REMOVE_UFW_RULE}" == "no" ]]; then
    return 0
  fi

  if ! command -v ufw >/dev/null 2>&1; then
    log "ufw not installed; skipping firewall cleanup"
    return 0
  fi

  port="$(configured_port)"
  ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
  log "removed ufw allow rule for tcp/${port}"
}

remove_service_user() {
  [[ "${PLATFORM}" == macOS ]] && return 0
  if [[ "${REMOVE_USER}" == "0" || "${REMOVE_USER}" == "false" || "${REMOVE_USER}" == "no" ]]; then
    return 0
  fi

  userdel "${RUN_USER}" >/dev/null 2>&1 || true
  groupdel "${RUN_GROUP}" >/dev/null 2>&1 || true
  log "removed user/group ${RUN_USER}:${RUN_GROUP} when present"
}

case "${1:-uninstall}" in
  uninstall)
    case "$(uname -s):${PLATFORM}" in
      Linux:linux|Darwin:macOS) ;;
      *) die "PLATFORM does not match this host" ;;
    esac
    [[ "${SERVICE_SCOPE}" != user || "${EUID}" -ne 0 ]] || die "run SERVICE_SCOPE=user without sudo"
    need_root
    remove_firewall_rule
    remove_service
    remove_files
    remove_service_user
    log "uninstall complete"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "unknown action: $1"
    ;;
esac
