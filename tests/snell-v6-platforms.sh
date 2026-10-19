#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/../snell-v6.sh"
load_functions() {
  eval "$(awk '/^case "\$\{ACTION\}" in/{exit} {print}' "${INSTALLER}")"
}
assert_eq() { [[ "$1" == "$2" ]] || { printf 'FAIL: expected %s, got %s\n' "$1" "$2" >&2; exit 1; }; }
for platform in linux macOS; do
  (
    PLATFORM="$platform"
    ARCH=arm64
    VERSION=auto
    load_functions
    fetch_release_notes() {
      printf '%s\n' \
        https://dl.nssurge.com/snell/snell-server-v6.0.0-linux-aarch64.zip \
        https://dl.nssurge.com/snell/snell-server-v6.0.0-macOS-arm64.zip \
        https://dl.nssurge.com/snell/snell-server-v6.1.0-linux-amd64.zip
    }
    remote_url_exists() { return 1; }
    expected_arch=arm64
    [[ "$platform" != linux ]] || expected_arch=aarch64
    expected="https://dl.nssurge.com/snell/snell-server-v6.0.0-${platform}-${expected_arch}.zip"
    assert_eq "$expected" "$(latest_v6_url)"
    assert_eq v6.0.0 "$(extract_version_from_url "$expected")"
    assert_eq "v6.0.0: ${expected_arch}" "$(VERSION=v6.0.0 available_arches)"
    assert_eq "$expected" "$(VERSION=v6.0.0 resolve_download_url)"
    fetch_release_notes() { return 1; }
    remote_url_exists() { [[ "$1" == "$expected" ]]; }
    assert_eq "$expected" "$(latest_v6_url)"
  )
done
(
  PLATFORM=macOS
  ARCH=arm64
  SERVICE_SCOPE=user
  load_functions
  assert_eq "gui/$(id -u)" "$LAUNCH_DOMAIN"
  assert_eq "$(id -un)" "$FILE_OWNER"
  assert_eq 600 "$CONFIG_MODE"
  assert_eq "${HOME}/Library/Application Support/snell-v6" "$INSTALL_ROOT"
  if command -v plutil >/dev/null; then
    temp="$(mktemp -d)"
    trap 'rm -rf "$temp"' EXIT
    SERVICE_FILE="$temp/service.plist"
    CURRENT_BIN="$temp/space & <tag>/bin"
    CONFIG_FILE="$temp/conf & settings"
    write_service_file
    plutil -lint "$SERVICE_FILE"
    # Validate XML escaping and the argument array, including spaces.
    python3 - "$SERVICE_FILE" "$CURRENT_BIN" "$CONFIG_FILE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    data = plistlib.load(f)
assert data['ProgramArguments'] == [sys.argv[2], '-c', sys.argv[3]]
assert 'UserName' not in data
PY
    SERVICE_SCOPE=system
    RUN_USER=nobody
    RUN_GROUP=nobody
    write_service_file
    python3 - "$SERVICE_FILE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    data = plistlib.load(f)
assert data['UserName'] == data['GroupName'] == 'nobody'
PY
  fi
)
(
  PLATFORM=macOS
  ARCH=arm64
  load_functions
  temp="$(mktemp -d)"
  trap 'rm -rf "$temp"' EXIT
  CURRENT_BIN="$temp/current"
  printf '#!/bin/sh\nexit 0\n' > "$temp/snell-server-v6.0.0rc2"
  chmod +x "$temp/snell-server-v6.0.0rc2"
  cp "$temp/snell-server-v6.0.0rc2" "$temp/snell-server-v6.0.0"
  ln -s "$temp/snell-server-v6.0.0" "$CURRENT_BIN"
  restart_service() { return 0; }
  rollback_binary_after_failed_restart "$temp/snell-server-v6.0.0rc2"
  assert_eq v6.0.0rc2 "$(current_installed_version)"
)
# launchd may reject bootstrap while a just-removed job is exiting.
(
  PLATFORM=macOS
  ARCH=arm64
  load_functions
  temp="$(mktemp -d)"
  trap 'rm -rf "$temp"' EXIT
  printf '0\n' > "$temp/attempts"
  sleep() { :; }
  launchctl() {
    case "$1" in
      print|bootout|enable) return 0 ;;
      bootstrap)
        count="$(cat "$temp/attempts")"
        count=$((count + 1))
        printf '%s\n' "$count" > "$temp/attempts"
        [[ "$count" -gt 1 ]] ;;
    esac
  }
  service_is_active() { return 0; }
  restart_service
  assert_eq 2 "$(cat "$temp/attempts")"
  launchctl() { [[ "$1" != bootstrap ]]; }
  if restart_service >/dev/null 2>&1; then
    printf 'FAIL: failed bootstrap must fail restart\n' >&2
    exit 1
  fi
)
printf 'Snell platform tests passed\n'
