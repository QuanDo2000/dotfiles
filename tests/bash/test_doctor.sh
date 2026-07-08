#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  unset -f command 2>/dev/null || true
  source_scripts utils.sh doctor.sh
}

teardown() {
  cleanup_test_env
}

link_valid_core_dotfiles() {
  local root="${1:-$DOTFILES_DIR}"
  ln -s "$root/.zshrc" "$HOME/.zshrc"
  ln -s "$root/bin/dotfile" "$HOME/.local/bin/dotfile"
}

test_doctor_symlink_valid() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

  if [[ ! -L "$HOME/.zshrc" ]]; then
    echo "  Expected $HOME/.zshrc to be a symlink" >> "$ERROR_FILE"
    return
  fi
  local link_target
  link_target="$(readlink "$HOME/.zshrc")"
  assert_contains "$link_target" "$DOTFILES_DIR"
}

test_doctor_file_not_symlink() {
  echo "not a symlink" > "$HOME/.zshrc"
  if [[ -L "$HOME/.zshrc" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$HOME/.zshrc"
}

test_doctor_error_count() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(doctor 2>&1) || true
  assert_contains "$output" "issue(s) found"
}

test_doctor_is_a_small_smoke_check() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(doctor 2>&1) || true
  if [[ "$output" == *"starship"* || "$output" == *"zsh plugin"* || "$output" == *"tmux plugin"* ]]; then
    echo "  FAILED: doctor should only smoke-check core Home Manager links" >> "$ERROR_FILE"
  fi
}

test_doctor_symlink_wrong_target() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/other"
  echo "content" > "$HOME/other/.zshrc"
  ln -s "$HOME/other/.zshrc" "$HOME/.zshrc"
  local output
  output=$(doctor 2>&1) || true
  assert_contains "$output" "expected"
}

test_doctor_requires_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  rm -f "$HOME/.local/bin/dotfile"

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" ".local/bin/dotfile not found"
}

test_doctor_accepts_repo_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  link_valid_core_dotfiles "/nix/store/example-dotfiles"

  local output
  output=$(OS_RELEASE="$osrel" doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_mac() {
  mock_uname Darwin
  link_valid_core_dotfiles "/nix/store/example-dotfiles"

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_arch() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  link_valid_core_dotfiles "$hm_dir"

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_debian() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  link_valid_core_dotfiles "$hm_dir"

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_doctor_reports_core_dotfile_conflicts() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  printf 'local shell edits\n' > "$HOME/.zshrc"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$os_release" doctor 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" ".zshrc exists but is not a symlink"
}

test_doctor_passes_with_home_manager_store_targets() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  link_valid_core_dotfiles "$hm_dir"

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "All checks passed"
}

test_doctor_skips_nix_eval_in_dry_mode() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  link_valid_core_dotfiles "$hm_dir"

  local command_calls="$TEST_TMPDIR/command-calls.log"
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "nix" ]]; then
      printf '/nix/store/fake/bin/nix\n'
      return 0
    fi
    if [[ "${1:-}" == "nix" ]]; then
      printf 'nix\n' >> "$command_calls"
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  DRY=true
  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "Skipping Nix evaluation in dry-run mode"
  if [[ -s "$command_calls" ]]; then
    echo "  FAILED: doctor called nix directly during dry-run" >> "$ERROR_FILE"
  fi
}

test_doctor_retries_nix_eval_with_temp_cache_after_fetcher_cache_failure() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  mkdir -p "$DOTFILES_DIR/config"
  printf '{ username = "quando"; hostName = "nixos"; }\n' > "$DOTFILES_DIR/config/host.nix"
  touch "$DOTFILES_DIR/flake.nix"

  local hm_dir="/nix/store/test-home-files"
  link_valid_core_dotfiles "$hm_dir"

  local calls="$TEST_TMPDIR/nix-calls.log"
  nix() {
    printf '%s\n' "${XDG_CACHE_HOME:-default}" >> "$calls"
    if [[ "$*" == *"--file"* ]]; then
      case "${@: -1}" in
        username) printf 'quando\n' ;;
        hostName) printf 'nixos\n' ;;
      esac
      return 0
    fi
    if [[ -z "${XDG_CACHE_HOME:-}" ]]; then
      printf "error: executing SQLite statement 'pragma synchronous = off': unable to open database file (in '$HOME/.cache/nix/fetcher-cache-v4.sqlite')\n" >&2
      return 1
    fi
    printf '/nix/store/test-system.drv\n'
  }
  export -f nix

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "All checks passed"
  assert_contains "$(tail -n 1 "$calls")" "dotfile-nix-cache."
}
