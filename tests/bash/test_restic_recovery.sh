#!/usr/bin/env bash
# Independent native recovery owns its file workspace under the existing budget.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_restic_recovery_smb_permissions() {
  local tool exit_code=0
  if [[ "$(uname -s)" != Linux ]]; then
    printf 'SKIP: recovery ACL integration requires Linux\n'
    return
  fi
  for tool in restic rclone setfacl getfacl; do
    if ! command -v "$tool" >/dev/null; then
      printf 'SKIP: recovery ACL integration requires %s\n' "$tool"
      return
    fi
  done
  python3 "$REPO_DIR/tests/nix/restic-recovery-permissions.py" "$REPO_DIR/config/arch-server/restic-recover" || exit_code=$?
  assert_equals "0" "$exit_code"
}
