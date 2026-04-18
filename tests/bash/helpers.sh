#!/bin/bash
# Shared helpers for all test files. Source this at the top of each test file.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTFILE_CMD="$REPO_DIR/dotfile"

# True on Git Bash / MSYS / Cygwin where Unix permission semantics and tools
# like chsh don't behave as on Linux/macOS. Uses OSTYPE (shell built-in) so
# it is not affected by tests that mock `uname`.
is_windows_bash() {
  case "${OSTYPE:-}" in
    msys*|cygwin*) return 0 ;;
    *) return 1 ;;
  esac
}


# Initialise a temp HOME with standard directories.
# Usage: init_test_env [DRY]   (DRY defaults to "false")
init_test_env() {
  export DRY="${1:-false}"
  export QUIET=false
  export FORCE=false
  TEST_TMPDIR="$(mktemp -d)"
  ORIG_HOME="$HOME"
  export HOME="$TEST_TMPDIR/home"
  export DOTFILES_DIR="$HOME/dotfiles"
  mkdir -p "$HOME" "$HOME/.config" "$HOME/.local/bin"
}

# Restore HOME, clean up temp dir, remove uname mock.
cleanup_test_env() {
  export HOME="$ORIG_HOME"
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME 2>/dev/null || true
  unset __MOCK_UNAME_M 2>/dev/null || true
  rm -rf "$TEST_TMPDIR"
}

# Source one or more scripts from scripts/.
# Usage: source_scripts utils.sh symlinks.sh
# Always also sources platform.sh (required by packages.sh and symlinks.sh).
source_scripts() {
  for script in "$@"; do
    source "$REPO_DIR/scripts/$script"
  done
  # shellcheck disable=SC1091
  source "$REPO_DIR/scripts/platform.sh"
}

# Internal: install a uname() that respects __MOCK_UNAME and __MOCK_UNAME_M.
# Falls through to the real uname for whichever env var is unset.
_install_uname_mock() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "${__MOCK_UNAME_M:-$(command uname -m)}"
    else
      echo "${__MOCK_UNAME:-$(command uname)}"
    fi
  }
  export -f uname
}

# Override uname (no args) to return the given OS string.
# Usage: mock_uname Darwin
mock_uname() {
  export __MOCK_UNAME="$1"
  _install_uname_mock
}

# Override uname -m to return the given architecture string.
# Usage: mock_uname_m aarch64
mock_uname_m() {
  export __MOCK_UNAME_M="$1"
  _install_uname_mock
}

# Create the standard dotfiles/config/{shared,unix,mac} directories under DOTFILES_DIR.
create_dotfiles_dirs() {
  mkdir -p "$DOTFILES_DIR/config/shared" "$DOTFILES_DIR/config/unix" "$DOTFILES_DIR/config/mac"
}
