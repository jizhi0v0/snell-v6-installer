#!/usr/bin/env bash

# shellcheck disable=SC2034,SC2329

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALLER="${REPO_ROOT}/snell-v6.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "${actual}" == "${expected}" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

source_installer_functions() {
  # Load function definitions without running the installer's action dispatcher.
  eval "$(awk '/^case "\$\{ACTION\}" in/{exit} {print}' "${INSTALLER}")"
}

mock_install_command() {
  install() {
    local mode=""
    local src dest count
    local -a operands=()
    local -a dirs=()

    if [[ "${1:-}" == "-d" ]]; then
      shift
      while (($#)); do
        case "$1" in
          -m)
            mode="$2"
            shift 2
            ;;
          --)
            shift
            ;;
          -*)
            shift
            ;;
          *)
            dirs+=("$1")
            shift
            ;;
        esac
      done

      for dest in "${dirs[@]}"; do
        mkdir -p "${dest}"
        [[ -n "${mode}" ]] && chmod "${mode}" "${dest}"
      done
      return 0
    fi

    while (($#)); do
      case "$1" in
        -m)
          mode="$2"
          shift 2
          ;;
        -o|-g)
          shift 2
          ;;
        -D|--)
          shift
          ;;
        -*)
          shift
          ;;
        *)
          operands+=("$1")
          shift
          ;;
      esac
    done

    count="${#operands[@]}"
    (( count >= 2 )) || return 1
    src="${operands[$((count - 2))]}"
    dest="${operands[$((count - 1))]}"
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    [[ -n "${mode}" ]] && chmod "${mode}" "${dest}"
  }
}

with_temp_install_root() {
  local tmp="$1"

  INSTALL_ROOT="${tmp}/opt/snell"
  RELEASES_DIR="${INSTALL_ROOT}/releases"
  BIN_DIR="${INSTALL_ROOT}/bin"
  CONF_DIR="${INSTALL_ROOT}/conf"
  CURRENT_BIN="${BIN_DIR}/snell-server-v6"
  CONFIG_FILE="${CONF_DIR}/snell-server-v6.conf"
  SERVICE_FILE="${tmp}/snell-v6.service"
  RUN_GROUP="staff"
}

write_existing_config() {
  mkdir -p "${CONF_DIR}"
  {
    printf '[snell-server]\n'
    printf 'listen = %s\n' "$1"
    printf 'psk = keep-me\n'
    printf 'dns-ip-preference = ipv4-only\n'
    printf 'dns = 1.1.1.1\n'
    printf 'egress-interface = eth9\n'
  } >"${CONFIG_FILE}"
}

test_version_ordering() (
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions

  assert_eq "update" "$(version_relation v6.0.0b2 v6.0.0)" "stable should sort after same-base beta"
  assert_eq "downgrade" "$(version_relation v6.0.0 v6.0.0b2)" "beta should sort before same-base stable"
  assert_eq "reinstall" "$(version_relation v6.0.0b2 v6.0.0b2)" "same version should be reinstall"
)

test_port_validation() (
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions

  validate_port 1
  validate_port 65535
  assert_eq "80" "$(normalize_port_value 00080)" "ports should normalize decimal values"

  if (validate_port 0) >/dev/null 2>&1; then fail "port 0 should be invalid"; fi
  if (validate_port 65536) >/dev/null 2>&1; then fail "port 65536 should be invalid"; fi
  if (validate_port abc) >/dev/null 2>&1; then fail "non-numeric port should be invalid"; fi
)

test_listen_validation() (
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions
  ipv6_available() { return 0; }

  validate_listen_value "0.0.0.0:7177"
  validate_listen_value "0.0.0.0:7177,[::]:7177"

  if (validate_listen_value "0.0.0.0") >/dev/null 2>&1; then fail "listen without port should be invalid"; fi

  ipv6_available() { return 1; }
  if (validate_listen_value "[::]:7177") >/dev/null 2>&1; then fail "IPv6 listen should fail when IPv6 is unavailable"; fi
)

test_first_install_port_preparation() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=18080
  ASSUME_YES=1
  source_installer_functions
  service_is_active() { return 1; }
  port_is_listening() { return 1; }

  prepare_config_inputs
  assert_eq "0.0.0.0:18080" "${LISTEN}" "first install should use explicit PORT"
)

test_normal_update_ignores_port_without_overwrite() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=2222
  ASSUME_YES=1
  source_installer_functions
  port_is_listening() { fail "port check should not run when preserving config"; }

  prepare_config_inputs
  assert_eq "" "${LISTEN}" "normal update should not apply PORT to existing config"
)

test_normal_update_reports_existing_listen_without_overwrite() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b2
  LISTEN="0.0.0.0:2222"
  ASSUME_YES=1
  source_installer_functions
  port_is_listening() { fail "port check should not run when preserving config"; }

  prepare_config_inputs
  assert_eq "127.0.0.1:1111" "$(planned_listen_value)" "plan should report existing listen when config is preserved"
  assert_eq "1111" "$(configured_port)" "firewall helper should use existing listen when config is preserved"
)

test_config_overwrite_applies_explicit_port_and_preserves_values() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=2222
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  mock_install_command
  service_is_active() { return 0; }
  port_is_listening() { return 1; }

  prepare_config_inputs
  write_config >/dev/null

  grep -qx 'listen = 0.0.0.0:2222' "${CONFIG_FILE}" || fail "explicit PORT should rewrite listen"
  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "PSK should be preserved when not overridden"
  grep -qx 'dns-ip-preference = ipv4-only' "${CONFIG_FILE}" || fail "dns-ip-preference should be preserved"
  grep -qx 'dns = 1.1.1.1' "${CONFIG_FILE}" || fail "dns should be preserved"
  grep -qx 'egress-interface = eth9' "${CONFIG_FILE}" || fail "egress-interface should be preserved"
  [[ -n "${CONFIG_BACKUP_PATH}" && -f "${CONFIG_BACKUP_PATH}" ]] || fail "config backup should be recorded"
)

test_first_install_rejects_occupied_port() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=2222
  ASSUME_YES=1
  source_installer_functions
  service_is_active() { return 1; }
  port_is_listening() { [[ "$1" == "2222" ]]; }

  if (prepare_config_inputs) >/dev/null 2>&1; then
    fail "first install should reject an occupied target port"
  fi
)

test_active_service_same_port_is_not_false_positive() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "0.0.0.0:2222"
  ARCH=amd64
  VERSION=v6.0.0b2
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  service_is_active() { return 0; }
  port_is_listening() { [[ "$1" == "2222" ]]; }

  prepare_config_inputs
)

test_changed_port_conflict_is_rejected() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "0.0.0.0:1111"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=2222
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  service_is_active() { return 0; }
  port_is_listening() { [[ "$1" == "2222" ]]; }

  if (prepare_config_inputs) >/dev/null 2>&1; then
    fail "changed port should be rejected when another listener already uses it"
  fi
)

test_downgrade_guard() (
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions
  current_installed_path() { printf '/opt/snell/releases/snell-server-v6.0.0b2\n'; }

  if (ensure_not_downgrade v6.0.0b1) >/dev/null 2>&1; then
    fail "downgrade should be refused by default"
  fi

  ALLOW_DOWNGRADE=1
  ensure_not_downgrade v6.0.0b1
)

test_config_restore_after_failed_restart() (
  local tmp failed_count
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b2
  PORT=2222
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  mock_install_command
  service_is_active() { return 1; }
  port_is_listening() { return 1; }

  prepare_config_inputs
  write_config >/dev/null
  restore_config_after_failed_restart >/dev/null

  grep -qx 'listen = 127.0.0.1:1111' "${CONFIG_FILE}" || fail "failed rewrite should restore old listen"
  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "failed rewrite should restore old PSK"
  failed_count="$(find "${CONF_DIR}" -name 'snell-server-v6.conf.failed.*' | wc -l | tr -d ' ')"
  assert_eq "1" "${failed_count}" "failed config should be retained for debugging"
)

test_binary_rollback() (
  local tmp previous current
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions
  systemctl() { return 0; }
  restart_service() { return 0; }

  mkdir -p "${RELEASES_DIR}" "${BIN_DIR}"
  previous="${RELEASES_DIR}/snell-server-v6.0.0b2"
  current="${RELEASES_DIR}/snell-server-v6.0.0"
  : >"${previous}"
  : >"${current}"
  chmod +x "${previous}" "${current}"
  ln -s "${current}" "${CURRENT_BIN}"

  rollback_binary_after_failed_restart "${previous}" >/dev/null
  assert_eq "${previous}" "$(readlink "${CURRENT_BIN}")" "rollback should restore the previous binary symlink"
)

main() {
  test_version_ordering
  test_port_validation
  test_listen_validation
  test_first_install_port_preparation
  test_normal_update_ignores_port_without_overwrite
  test_normal_update_reports_existing_listen_without_overwrite
  test_config_overwrite_applies_explicit_port_and_preserves_values
  test_first_install_rejects_occupied_port
  test_active_service_same_port_is_not_false_positive
  test_changed_port_conflict_is_rejected
  test_downgrade_guard
  test_config_restore_after_failed_restart
  test_binary_rollback

  printf 'snell-v6 regression tests passed\n'
}

main "$@"
