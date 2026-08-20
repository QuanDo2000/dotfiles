#!/usr/bin/env bash
set -Eeuo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${SERVICE_STATE_BACKUP_ROOT:-/}"
skip_systemd="${SERVICE_STATE_BACKUP_SKIP_SYSTEMD:-false}"

if [[ "$root" == / && "$EUID" != 0 ]]; then
  echo "Run with sudo: sudo $source_dir/install.sh" >&2
  exit 1
fi

bash -n "$source_dir/homelab-service-state-backup"

install_file() {
  local source=$1 destination=$2 mode=$3 temporary
  install -d "$(dirname "$destination")"
  temporary="$(mktemp "${destination}.new.XXXXXXXX")"
  install -m "$mode" "$source" "$temporary"
  mv -f "$temporary" "$destination"
}

install_file "$source_dir/homelab-service-state-backup" \
  "$root/usr/local/sbin/homelab-service-state-backup" 0700
install_file "$source_dir/homelab-service-state-backup.service" \
  "$root/etc/systemd/system/homelab-service-state-backup.service" 0644
install_file "$source_dir/homelab-service-state-backup.timer" \
  "$root/etc/systemd/system/homelab-service-state-backup.timer" 0644

[[ "$skip_systemd" == true ]] && exit 0

systemd-analyze verify \
  /etc/systemd/system/homelab-service-state-backup.service \
  /etc/systemd/system/homelab-service-state-backup.timer
systemctl daemon-reload
/usr/local/sbin/homelab-service-state-backup --check
install -d -m 0700 -o quando -g quando \
  /mnt/storage/Storage/Documents/HomelabBackups/service-state
systemctl enable --now homelab-service-state-backup.timer
