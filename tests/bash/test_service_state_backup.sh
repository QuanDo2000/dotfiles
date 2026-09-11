#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() { init_test_env; }
teardown() { cleanup_test_env; }

service_state_dir="$REPO_DIR/config/arch-server/service-state-backup"


test_installer_places_exact_service_state_backup_files_in_sandbox() {
  local root="$TEST_TMPDIR/root"

  SERVICE_STATE_BACKUP_ROOT="$root" \
    SERVICE_STATE_BACKUP_SKIP_SYSTEMD=true \
    bash "$service_state_dir/install.sh"

  assert_file_exists "$root/usr/local/sbin/homelab-service-state-backup"
  assert_file_exists "$root/etc/systemd/system/homelab-service-state-backup.service"
  assert_file_exists "$root/etc/systemd/system/homelab-service-state-backup.timer"
  assert_exit_code 0 cmp "$service_state_dir/homelab-service-state-backup" "$root/usr/local/sbin/homelab-service-state-backup"
  assert_exit_code 0 cmp "$service_state_dir/homelab-service-state-backup.service" "$root/etc/systemd/system/homelab-service-state-backup.service"
  assert_exit_code 0 cmp "$service_state_dir/homelab-service-state-backup.timer" "$root/etc/systemd/system/homelab-service-state-backup.timer"
  [[ -x "$root/usr/local/sbin/homelab-service-state-backup" ]] || echo "  backup script is not executable" >> "$ERROR_FILE"
  [[ ! -x "$root/etc/systemd/system/homelab-service-state-backup.service" ]] || echo "  service unit is unexpectedly executable" >> "$ERROR_FILE"
}


# Load function definitions only; never run the root backup against this host.
load_backup_functions() {
  source <(awk '/^require_root$/ { exit } { sub(/^declare -/, "declare -g"); print }' "$service_state_dir/homelab-service-state-backup")
  trap - EXIT INT TERM
}

test_backup_aborts_when_docker_inventory_fails() {
  local output status=0
  output="$(
    load_backup_functions
    docker() { return 42; }
    archive() { echo ARCHIVED; }
    backup_compose_project example /fixture/compose.yml
  )" || status=$?
  assert_equals 42 "$status"
  assert_not_contains "$output" ARCHIVED
}

test_backup_cleanup_reports_failed_restart() {
  local output status=0
  output="$(
    load_backup_functions
    docker() { return 42; }
    COMPOSE_RUNNING[/fixture/compose.yml]=app
    STOPPED_COMPOSE=(/fixture/compose.yml)
    cleanup
  )" 2>/dev/null || status=$?
  assert_equals 1 "$status"
}

test_backup_retains_record_when_restart_fails() {
  load_backup_functions
  docker() { return 42; }
  COMPOSE_RUNNING[/fixture/compose.yml]=app
  local status=0
  restart_compose /fixture/compose.yml || status=$?
  assert_equals 42 "$status"
  assert_equals app "${COMPOSE_RUNNING[/fixture/compose.yml]:-}"
}

test_backup_no_longer_depends_on_retired_homeserver() {
  if grep -q homeserver "$service_state_dir/homelab-service-state-backup"; then
    echo "  retired homeserver still referenced by service-state backup" >> "$ERROR_FILE"
  fi
}


test_arch_install_flow_installs_system_backup_after_home_manager_activation() {
  source_scripts utils.sh packages.sh
  local calls="$TEST_TMPDIR/calls"

  export DRY=false
  _install_native_bootstrap_packages() { :; }
  _home_manager_switch() { printf 'switch\n' >> "$calls"; }
  _install_arch_service_state_backup() { printf 'install\n' >> "$calls"; }

  install_arch

  assert_equals $'switch\ninstall' "$(<"$calls")"
}
