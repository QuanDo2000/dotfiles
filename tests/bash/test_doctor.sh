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

test_doctor_tool_found() {
  local output
  output=$(
    if command -v bash >/dev/null 2>&1; then
      success "bash found: $(command -v bash)"
    else
      fail_soft "bash not found"
    fi
  )
  assert_contains "$output" "bash found"
}

test_doctor_tool_missing() {
  local output
  output=$(
    if command -v nonexistent_tool_xyz >/dev/null 2>&1; then
      success "found"
    else
      fail_soft "nonexistent_tool_xyz not found"
    fi
  )
  assert_contains "$output" "nonexistent_tool_xyz not found"
}

test_doctor_symlink_valid() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.vimrc"
  ln -s "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"

  if [[ ! -L "$HOME/.vimrc" ]]; then
    echo "  Expected $HOME/.vimrc to be a symlink" >> "$ERROR_FILE"
    return
  fi
  local link_target
  link_target="$(readlink "$HOME/.vimrc")"
  assert_contains "$link_target" "$DOTFILES_DIR"
}

test_doctor_file_not_symlink() {
  echo "not a symlink" > "$HOME/.vimrc"
  if [[ -L "$HOME/.vimrc" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$HOME/.vimrc"
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
  echo "content" > "$HOME/other/.vimrc"
  ln -s "$HOME/other/.vimrc" "$HOME/.vimrc"
  local output
  output=$(doctor 2>&1) || true
  assert_contains "$output" "expected"
}

test_doctor_requires_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    echo "content" > "$DOTFILES_DIR/$f"
    mkdir -p "$(dirname "$HOME/$f")"
    ln -s "$DOTFILES_DIR/$f" "$HOME/$f"
  done
  rm -f "$HOME/.local/bin/dotfile"

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" ".local/bin/dotfile not found"
}

test_doctor_accepts_repo_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    echo "content" > "$DOTFILES_DIR/$f"
    mkdir -p "$(dirname "$HOME/$f")"
    ln -s "$DOTFILES_DIR/$f" "$HOME/$f"
  done
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "/nix/store/example-dotfiles/$f" "$HOME/$f"
  done
  ln -s "/nix/store/example-dotfiles/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_mac() {
  mock_uname Darwin
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "/nix/store/example-dotfiles/$f" "$HOME/$f"
  done
  ln -s "/nix/store/example-dotfiles/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_arch() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_doctor_accepts_home_manager_store_targets_on_debian() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_doctor_requires_nix_agent_tools_on_arch() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"

  local bin_dir="$TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codex"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codebase-memory-mcp"
  chmod +x "$bin_dir/codex" "$bin_dir/codebase-memory-mcp"

  local output
  output=$(PATH="$bin_dir:$PATH" OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "codex points to"
  assert_contains "$output" "codebase-memory-mcp points to"
  assert_contains "$output" "expected /nix/store"
}

test_doctor_requires_nix_agent_tools_on_debian() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"

  local bin_dir="$TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codex"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codebase-memory-mcp"
  chmod +x "$bin_dir/codex" "$bin_dir/codebase-memory-mcp"

  local output
  output=$(PATH="$bin_dir:$PATH" OS_RELEASE="$os_release" doctor 2>&1) || true
  assert_contains "$output" "codex points to"
  assert_contains "$output" "codebase-memory-mcp points to"
  assert_contains "$output" "expected /nix/store"
}

test_doctor_accepts_nix_agent_tools_on_mac() {
  mock_uname Darwin
  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(doctor 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_doctor_reports_home_manager_conflicts() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  printf 'local shell edits\n' > "$HOME/.zshrc"
  ln -s /nix/store/test-home-files/.vimrc "$HOME/.vimrc"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$os_release" doctor 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" ".zshrc exists but is not Home Manager-owned"
  assert_not_contains "$output" ".vimrc exists but is not Home Manager-owned"
}

test_doctor_passes_without_home_manager_conflicts() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "Home Manager-managed paths are clear"
  assert_contains "$output" "All checks passed"
}

test_doctor_reports_invalid_home_manager_manifest_kind() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  HM_MANAGED_PATHS_FILE="$TEST_TMPDIR/managed-paths"
  printf 'bad-kind example\n' > "$HM_MANAGED_PATHS_FILE"

  local output exit_code
  set +e
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$os_release" doctor 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unknown Home Manager managed path kind 'bad-kind'"
}

test_doctor_reports_obsidian_config_drift() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  mkdir -p "$OBSIDIAN_CONFIG_SOURCE" "$OBSIDIAN_CONFIG_VAULT"
  printf '{"vimMode":true}\n' > "$OBSIDIAN_CONFIG_SOURCE/app.json"
  printf '{"vimMode":false}\n' > "$OBSIDIAN_CONFIG_VAULT/app.json"

  local output exit_code
  set +e
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$os_release" doctor 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Obsidian config drift: app.json"
  assert_contains "$output" "Run 'dotfile -f obsidian-config' to apply tracked Obsidian config"
}

test_doctor_reports_obsidian_config_match() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  mkdir -p "$OBSIDIAN_CONFIG_SOURCE" "$OBSIDIAN_CONFIG_VAULT"
  printf '{"vimMode":true}\n' > "$OBSIDIAN_CONFIG_SOURCE/app.json"
  printf '{"vimMode":true}\n' > "$OBSIDIAN_CONFIG_VAULT/app.json"

  local output
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "Obsidian config matches tracked settings"
}

test_doctor_reports_missing_obsidian_config_source() {
  OBSIDIAN_CONFIG_SOURCE="$TEST_TMPDIR/missing-obsidian-config"

  local output
  output=$(_check_obsidian_config 2>&1)

  assert_contains "$output" "Skipping Obsidian config drift check: $OBSIDIAN_CONFIG_SOURCE not found"
}

test_doctor_skips_nix_eval_in_dry_mode() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  local hm_dir="/nix/store/test-home-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

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
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

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
