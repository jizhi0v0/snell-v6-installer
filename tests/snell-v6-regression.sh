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
  local listen="$1"
  local mode="${2:-}"

  mkdir -p "${CONF_DIR}"
  {
    printf '[snell-server]\n'
    printf 'listen = %s\n' "${listen}"
    printf 'psk = keep-me\n'
    if [[ -n "${mode}" ]]; then
      printf 'mode = %s\n' "${mode}"
    fi
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

  assert_eq "update" "$(version_relation v6.0.0b4 v6.0.0rc)" "RC should sort after same-base beta"
  assert_eq "update" "$(version_relation v6.0.0rc v6.0.0rc.1)" "numbered RC should sort after unnumbered RC"
  assert_eq "update" "$(version_relation v6.0.0rc.1 v6.0.0rc.2)" "RC sequence should sort numerically"
  assert_eq "update" "$(version_relation v6.0.0rc.2 v6.0.0rc.10)" "multi-digit RC sequence should sort numerically"
  assert_eq "update" "$(version_relation v6.0.0rc.2 v6.0.0)" "stable should sort after same-base RC"
  assert_eq "downgrade" "$(version_relation v6.0.0 v6.0.0rc.2)" "RC should sort before same-base stable"
  assert_eq "update" "$(version_relation v6.0.0b2 v6.0.0)" "stable should sort after same-base beta"
  assert_eq "downgrade" "$(version_relation v6.0.0 v6.0.0b2)" "beta should sort before same-base stable"
  assert_eq "reinstall" "$(version_relation v6.0.0rc.2 v6.0.0rc.2)" "same numbered RC should be reinstall"
  assert_eq "reinstall" "$(version_relation v6.0.0b2 v6.0.0b2)" "same version should be reinstall"
)

test_bilingual_relation_labels() (
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions

  assert_eq "install / 安装" "$(display_relation install)" "install relation should be bilingual"
  assert_eq "update / 更新" "$(display_relation update)" "update relation should be bilingual"
  assert_eq "reinstall / 重装" "$(display_relation reinstall)" "reinstall relation should be bilingual"
  assert_eq "downgrade / 降级" "$(display_relation downgrade)" "downgrade relation should be bilingual"
  assert_eq "unknown / 未知" "$(display_relation unknown)" "unknown relation should be bilingual"
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

test_mode_validation_and_version_gate() (
  ARCH=amd64
  VERSION=v6.0.0b3
  ASSUME_YES=1
  source_installer_functions

  validate_mode default
  validate_mode unshaped
  validate_mode unsafe-raw
  if (validate_mode raw) >/dev/null 2>&1; then fail "invalid mode should be rejected"; fi
  version_supports_mode v6.0.0b3
  version_supports_mode v6.0.0rc
  version_supports_mode v6.0.0rc.2
  version_supports_mode v6.0.0
  if (version_supports_mode v6.0.0b2) >/dev/null 2>&1; then fail "beta2 should not support mode"; fi
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

test_normal_update_rejects_mode_when_target_does_not_support_it() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "unshaped"
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions

  if (prepare_config_inputs v6.0.0b2) >/dev/null 2>&1; then
    fail "target beta2 should reject an existing mode config"
  fi
)

test_normal_update_requires_overwrite_for_explicit_mode() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b3
  MODE=unshaped
  ASSUME_YES=1
  source_installer_functions

  if (prepare_config_inputs v6.0.0b3) >/dev/null 2>&1; then
    fail "explicit MODE should require CONFIG_OVERWRITE=1 when config already exists"
  fi
)

test_b2_to_b3_update_migrates_default_mode() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  {
    printf 'shadow-tls = enabled\n'
    printf '[shadow-tls]\n'
    printf 'enabled = true\n'
  } >>"${CONFIG_FILE}"
  ARCH=amd64
  VERSION=v6.0.0b3
  ASSUME_YES=1
  source_installer_functions
  port_is_listening() { fail "port check should not run when preserving config"; }
  mock_install_command

  current_installed_path() { printf '%s/snell-server-v6.0.0b2\n' "${RELEASES_DIR}"; }

  assert_eq "update" "$(version_relation "$(current_installed_version)" v6.0.0b3)" "b2 to b3 should be an update"
  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "b2 to b3 mode migration should preserve existing config"
  grep -qx 'mode = default' "${CONFIG_FILE}" || fail "b2 to b3 update should explicitly write default mode"
  grep -qx 'shadow-tls = enabled' "${CONFIG_FILE}" || fail "mode migration should preserve unknown config keys"
  grep -qx '\[shadow-tls\]' "${CONFIG_FILE}" || fail "mode migration should preserve unknown sections"
  grep -qx 'enabled = true' "${CONFIG_FILE}" || fail "mode migration should preserve unknown section values"
  [[ -n "${CONFIG_BACKUP_PATH}" && -f "${CONFIG_BACKUP_PATH}" ]] || fail "mode migration should back up existing config"
)

test_b2_to_b3_update_allows_explicit_default_mode_migration() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111"
  ARCH=amd64
  VERSION=v6.0.0b3
  MODE=default
  ASSUME_YES=1
  source_installer_functions
  mock_install_command

  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'mode = default' "${CONFIG_FILE}" || fail "explicit MODE=default should be allowed during mode migration"
)

test_beta3_reinstall_preserves_mode_and_unknown_config_without_overwrite() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "unshaped"
  printf 'shadow-tls = enabled\n' >>"${CONFIG_FILE}"
  ARCH=amd64
  VERSION=v6.0.0b3
  ASSUME_YES=1
  source_installer_functions
  port_is_listening() { fail "port check should not run when preserving config"; }
  chown() { return 0; }
  chmod() { return 0; }

  current_installed_path() { printf '%s/snell-server-v6.0.0b3\n' "${RELEASES_DIR}"; }

  assert_eq "reinstall" "$(version_relation "$(current_installed_version)" v6.0.0b3)" "b3 to b3 should be a reinstall"
  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'mode = unshaped' "${CONFIG_FILE}" || fail "b3 reinstall should preserve existing mode"
  grep -qx 'shadow-tls = enabled' "${CONFIG_FILE}" || fail "b3 reinstall should preserve unknown config keys"
)

test_existing_invalid_mode_rejected_for_supported_target() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "raw"
  ARCH=amd64
  VERSION=v6.0.0b3
  ASSUME_YES=1
  source_installer_functions

  if (prepare_config_inputs v6.0.0b3) >/dev/null 2>&1; then
    fail "invalid existing mode should be rejected before restart"
  fi
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

test_beta3_first_install_writes_default_mode() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  ARCH=amd64
  VERSION=v6.0.0b3
  PORT=2222
  ASSUME_YES=1
  source_installer_functions
  mock_install_command
  service_is_active() { return 1; }
  port_is_listening() { return 1; }

  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'mode = default' "${CONFIG_FILE}" || fail "beta3 first install should write default mode"
)

test_beta3_config_overwrite_applies_explicit_mode() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "default"
  printf 'shadow-tls = enabled\n' >>"${CONFIG_FILE}"
  ARCH=amd64
  VERSION=v6.0.0b3
  MODE=unshaped
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  mock_install_command
  service_is_active() { return 0; }
  port_is_listening() { return 1; }

  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'mode = unshaped' "${CONFIG_FILE}" || fail "explicit MODE should rewrite mode"
  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "mode rewrite should preserve PSK"
  grep -qx 'shadow-tls = enabled' "${CONFIG_FILE}" || fail "mode rewrite should preserve unknown config keys"
)

test_beta3_config_overwrite_preserves_existing_mode() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "unsafe-raw"
  ARCH=amd64
  VERSION=v6.0.0b3
  CONFIG_OVERWRITE=1
  ASSUME_YES=1
  source_installer_functions
  mock_install_command
  service_is_active() { return 0; }
  port_is_listening() { return 1; }

  prepare_config_inputs v6.0.0b3
  write_config >/dev/null

  grep -qx 'mode = unsafe-raw' "${CONFIG_FILE}" || fail "config rewrite should preserve existing mode when MODE is not set"
  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "mode-preserving rewrite should keep PSK"
)

test_mode_requires_beta3_when_writing_config() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  ARCH=amd64
  VERSION=v6.0.0b2
  MODE=unshaped
  PORT=2222
  ASSUME_YES=1
  source_installer_functions
  service_is_active() { return 1; }
  port_is_listening() { return 1; }

  if (prepare_config_inputs v6.0.0b2) >/dev/null 2>&1; then
    fail "MODE should require beta3 or newer when writing config"
  fi
)

test_beta3_to_b2_downgrade_guard_and_mode_rewrite() (
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  with_temp_install_root "${tmp}"
  write_existing_config "127.0.0.1:1111" "unshaped"
  ARCH=amd64
  VERSION=v6.0.0b2
  ASSUME_YES=1
  source_installer_functions
  current_installed_path() { printf '%s/snell-server-v6.0.0b3\n' "${RELEASES_DIR}"; }

  if (ensure_not_downgrade v6.0.0b2) >/dev/null 2>&1; then
    fail "b3 to b2 should be refused without ALLOW_DOWNGRADE=1"
  fi

  ALLOW_DOWNGRADE=1
  ensure_not_downgrade v6.0.0b2

  if (prepare_config_inputs v6.0.0b2) >/dev/null 2>&1; then
    fail "b3 to b2 with mode config should require CONFIG_OVERWRITE=1"
  fi

  CONFIG_OVERWRITE=1
  service_is_active() { return 0; }
  port_is_listening() { return 1; }
  mock_install_command
  prepare_config_inputs v6.0.0b2
  write_config >/dev/null

  grep -qx 'psk = keep-me' "${CONFIG_FILE}" || fail "downgrade rewrite should preserve PSK"
  if grep -q '^mode[[:space:]]*=' "${CONFIG_FILE}"; then
    fail "downgrade rewrite to beta2 should remove unsupported mode"
  fi
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

test_auto_resolves_curated_beta_when_notes_lag() (
  ARCH=amd64
  VERSION=auto
  source_installer_functions
  SNELL_V6_KNOWN_VERSIONS="v6.0.0b3 v6.0.0b4"
  fetch_release_notes() {
    printf '%s\n' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-amd64.zip' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-aarch64.zip'
  }
  remote_url_exists() {
    case "$1" in
      *snell-server-v6.0.0b4-linux-amd64.zip) return 0 ;;
      *snell-server-v6.0.0b4-linux-aarch64.zip) return 0 ;;
      *) return 1 ;;
    esac
  }

  assert_eq "v6.0.0b4" "$(latest_v6_version)" "auto should resolve the curated beta when notes lag"
  assert_eq "https://dl.nssurge.com/snell/snell-server-v6.0.0b4-linux-amd64.zip" "$(latest_v6_url)" \
    "latest url should use the curated beta for the current arch"
  assert_eq "v6.0.0b4: aarch64 amd64" "$(VERSION=v6.0.0b4 available_arches)" \
    "arches should list only the verified curated arches"
)

test_auto_resolves_numbered_release_candidate_from_notes() (
  ARCH=amd64
  VERSION=auto
  source_installer_functions
  SNELL_V6_KNOWN_VERSIONS="v6.0.0b4 v6.0.0rc"
  fetch_release_notes() {
    printf '%s\n' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0b4-linux-amd64.zip' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0rc-linux-amd64.zip' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0rc.1-linux-amd64.zip' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0rc.2-linux-amd64.zip' \
      'https://dl.nssurge.com/snell/snell-server-v6.0.0rc.2-linux-aarch64.zip'
  }
  remote_url_exists() { return 1; }

  assert_eq "v6.0.0rc.2" "$(latest_v6_version)" "auto should select the highest numbered RC"
  assert_eq "https://dl.nssurge.com/snell/snell-server-v6.0.0rc.2-linux-amd64.zip" "$(latest_v6_url)" \
    "latest URL should use the highest numbered RC for the current arch"
  assert_eq "v6.0.0rc.2: aarch64 amd64" "$(VERSION=v6.0.0rc.2 available_arches)" \
    "arches should list packages for a numbered RC"
)

test_auto_ignores_curated_beta_that_is_not_published() (
  ARCH=amd64
  VERSION=auto
  source_installer_functions
  SNELL_V6_KNOWN_VERSIONS="v6.0.0b3 v6.0.0b4 v6.0.0b5"
  fetch_release_notes() {
    printf '%s\n' 'https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-amd64.zip'
  }
  remote_url_exists() { return 1; }

  assert_eq "v6.0.0b3" "$(latest_v6_version)" "unpublished curated builds must be ignored"
  assert_eq "https://dl.nssurge.com/snell/snell-server-v6.0.0b3-linux-amd64.zip" "$(latest_v6_url)" \
    "latest url should fall back to the release-notes build"
)

test_auto_falls_back_to_curated_when_notes_unavailable() (
  ARCH=amd64
  VERSION=auto
  source_installer_functions
  SNELL_V6_KNOWN_VERSIONS="v6.0.0b4 v6.0.0rc"
  fetch_release_notes() { return 1; }
  remote_url_exists() {
    case "$1" in
      *snell-server-v6.0.0rc-linux-amd64.zip) return 0 ;;
      *) return 1 ;;
    esac
  }

  assert_eq "v6.0.0rc" "$(latest_v6_version)" "should fall back to the curated RC when notes are unreachable"
)

main() {
  test_version_ordering
  test_bilingual_relation_labels
  test_port_validation
  test_listen_validation
  test_mode_validation_and_version_gate
  test_first_install_port_preparation
  test_normal_update_ignores_port_without_overwrite
  test_normal_update_rejects_mode_when_target_does_not_support_it
  test_normal_update_requires_overwrite_for_explicit_mode
  test_b2_to_b3_update_migrates_default_mode
  test_b2_to_b3_update_allows_explicit_default_mode_migration
  test_beta3_reinstall_preserves_mode_and_unknown_config_without_overwrite
  test_existing_invalid_mode_rejected_for_supported_target
  test_normal_update_reports_existing_listen_without_overwrite
  test_config_overwrite_applies_explicit_port_and_preserves_values
  test_beta3_first_install_writes_default_mode
  test_beta3_config_overwrite_applies_explicit_mode
  test_beta3_config_overwrite_preserves_existing_mode
  test_mode_requires_beta3_when_writing_config
  test_beta3_to_b2_downgrade_guard_and_mode_rewrite
  test_first_install_rejects_occupied_port
  test_active_service_same_port_is_not_false_positive
  test_changed_port_conflict_is_rejected
  test_downgrade_guard
  test_config_restore_after_failed_restart
  test_binary_rollback
  test_auto_resolves_curated_beta_when_notes_lag
  test_auto_resolves_numbered_release_candidate_from_notes
  test_auto_ignores_curated_beta_that_is_not_published
  test_auto_falls_back_to_curated_when_notes_unavailable

  printf 'snell-v6 regression tests passed\n'
}

main "$@"
