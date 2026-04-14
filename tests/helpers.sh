#!/bin/bash
# Shared helpers for all test files. Source this at the top of each test file.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILE_CMD="$REPO_DIR/shared/bin/dotfile"

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

# Override uname to return the given platform string.
# Usage: mock_uname Darwin
mock_uname() {
  local platform="$1"
  eval "uname() { echo '$platform'; }"
  export -f uname
}

# Create the standard dotfiles/{shared,unix,mac} directories under DOTFILES_DIR.
create_dotfiles_dirs() {
  mkdir -p "$DOTFILES_DIR/shared" "$DOTFILES_DIR/unix" "$DOTFILES_DIR/mac"
}

# Set the three symlink-control locals to false.
# Must be called (not sourced) inside the test function so the variables
# are local to the caller.
# Usage: eval "$(init_symlink_vars)"
init_symlink_vars() {
  echo 'local overwrite_all=false backup_all=false skip_all=false'
}
