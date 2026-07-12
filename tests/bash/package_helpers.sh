#!/usr/bin/env bash
# Shared setup for scripts/packages.sh test suites.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh
  calls="$TEST_TMPDIR/nix.log"
  nix() {
    if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" ]]; then
      case "${5:-}" in
        username) printf 'testuser\n'; return ;;
        hostName) printf 'testhost\n'; return ;;
      esac
    fi
    printf 'nix %s\n' "$*" >> "$calls"
  }
}

teardown() {
  cleanup_test_env
}
