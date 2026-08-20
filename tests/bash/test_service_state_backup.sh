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
