#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export DOTFILE_DOCTOR_SKIP_NEOVIM_RUNTIME=true
}

teardown() {
  unset DOTFILE_DOCTOR_SKIP_NEOVIM_RUNTIME
  rm -rf "$TEST_HOME"
}

link_core_dotfiles() {
  mkdir -p "$HOME/.local/bin"
  local f src
  ln -s "$REPO_DIR/config/unix/.zshrc.base" "$HOME/.zshrc"
  mkdir -p "$HOME/.config/tmux" "$HOME/.config/git"
  ln -s "$REPO_DIR/config/unix/.tmux.conf" "$HOME/.config/tmux/tmux.conf"
  ln -s "$REPO_DIR/config/shared/.gitconfig" "$HOME/.config/git/config"
  ln -s "$DOTFILE_CMD" "$HOME/.local/bin/dotfile"
  mkdir -p "$HOME/.config/nvim" "$HOME/.config/systemd/user" "$HOME/.codex" "$HOME/.pi/agent"
  ln -s "$REPO_DIR/config/shared/config/nvim/init.lua" "$HOME/.config/nvim/init.lua"
  ln -s "$REPO_DIR/config/shared/config/nvim/init.lua" "$HOME/.config/nvim/fff-nvim-backend"
  : > "$HOME/.codex/config.toml"
  : > "$HOME/.pi/agent/settings.json"
  : > "$HOME/.pi/agent/mcp.json"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/fff-mcp-agent"
  chmod +x "$HOME/.local/bin/fff-mcp-agent"
  : > "$TEST_HOME/obsidian-sync.service"
  ln -s "$TEST_HOME/obsidian-sync.service" "$HOME/.config/systemd/user/obsidian-sync.service"
}

assert_checked_flow() {
  local output="$1"
  local pulls_repo="$2"
  local expected_checks="${3:-2}"

  assert_equals "$expected_checks" "$(grep -c "Verifying symlinks" <<<"$output")"
  local expected_skips=1
  [[ "$pulls_repo" == "true" ]] && expected_skips=2
  assert_equals "$expected_skips" "$(grep -c "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true" <<<"$output")"
  if [[ "$pulls_repo" == "true" ]]; then
    assert_contains "$output" "Updating dotfiles repo"
  else
    assert_not_contains "$output" "Updating dotfiles repo"
  fi
}

test_zsh_vi_insert_mode_can_delete_pasted_text() {
  local config
  config="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$config" "bindkey -M viins '^?' backward-delete-char"
  assert_contains "$config" "bindkey -M viins '^H' backward-delete-char"
}

test_help_exits_zero() {
  local output
  output=$(bash "$DOTFILE_CMD" -h 2>&1)
  assert_exit_code 0 bash "$DOTFILE_CMD" -h
  assert_contains "$output" "Usage"
  assert_contains "$output" "Commands"
  assert_contains "$output" "Options"
  assert_contains "$output" "update [ai]"
  assert_contains "$output" "Refresh all managed dependency pins"
  assert_contains "$output" "Update only AI tools and configs"
  assert_contains "$output" "codex"
  assert_contains "$output" "Update pinned Codex release package"
  assert_contains "$output" "lix-installer"
  assert_contains "$output" "Update pinned Lix installer checksums"
  assert_contains "$output" "obsidian-headless"
  assert_contains "$output" "Update pinned Obsidian Headless package"
  assert_contains "$output" "doctor"
  assert_contains "$output" "Detect dotfile and Nix issues"
  assert_contains "$output" "Bootstrap Obsidian Sync login and vault setup"
  assert_not_contains "$output" "obsidian-config"
}

test_dotfiles_dir_override_controls_unix_entrypoint() {
  local launcher="$TEST_HOME/dotfile-copy"
  cp "$DOTFILE_CMD" "$launcher"

  local output exit_code
  set +e
  output=$(DOTFILES_DIR="$REPO_DIR" bash "$launcher" --help 2>&1)
  exit_code=$?
  set -e

  assert_equals "0" "$exit_code"
  assert_contains "$output" "Usage"
  assert_not_contains "$output" "scripts/utils.sh"
}

test_doctor_command_runs_with_health_checks() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  assert_exit_code 0 env DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$osrel" bash "$DOTFILE_CMD" doctor
}

test_doctor_fast_skips_nix_eval() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" doctor --fast 2>&1)

  assert_contains "$output" "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true"
  assert_contains "$output" "All checks passed"
}

test_dry_run_default_command() {
  # Unix installer does not target Windows (Windows has its own PowerShell setup).
  is_windows_bash && return 0
  link_core_dotfiles
  with_nix_agent_tools

  local output exit_code
  set +e
  output=$(bash "$DOTFILE_CMD" --dry 2>&1)
  exit_code=$?
  set -e

  assert_equals "0" "$exit_code"
  assert_contains "$output" "Installing packages"
  local repo_line packages_line
  repo_line="$(grep -n "Updating dotfiles repo" <<<"$output" | head -n1 | cut -d: -f1)"
  packages_line="$(grep -n "Installing packages" <<<"$output" | head -n1 | cut -d: -f1)"
  if (( repo_line >= packages_line )); then
    echo "  FAILED: dotfile all should update repo before installing packages" >> "$ERROR_FILE"
  fi
  assert_not_contains "$output" "Updating packages"
}

test_all_does_not_run_obsidian_bootstrap() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  link_core_dotfiles
  with_nix_agent_tools

  printf 'ID=arch\n' > "$osrel"

  local output
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry all 2>&1)
  assert_not_contains "$output" "Setting up Obsidian headless sync"
  assert_contains "$output" "Verifying symlinks"
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_readme_matches_key_help_text() {
  local readme_text
  readme_text="$(<"$REPO_DIR/README.md")"
  assert_contains "$readme_text" "### Unix Commands"
  assert_contains "$readme_text" "update [ai]"
  assert_contains "$readme_text" "Update only AI tools and configs"
  assert_contains "$readme_text" 'AI-only updates use the same isolated validation'
  assert_contains "$readme_text" 'diff review, and approval boundary'
  assert_contains "$readme_text" "obsidian    Bootstrap Obsidian Sync login and vault setup"
  assert_contains "$readme_text" "codex       Update pinned Codex release package"
  assert_contains "$readme_text" "lix-installer"
  assert_contains "$readme_text" "Update pinned Lix installer checksums"
  assert_contains "$readme_text" "obsidian-headless"
  assert_contains "$readme_text" "Update pinned Obsidian Headless package"
  assert_contains "$readme_text" "doctor [--fast]"
  assert_contains "$readme_text" "Detect dotfile and Nix issues"
  assert_contains "$readme_text" "Home Manager owns tracked Obsidian settings"
  assert_contains "$readme_text" 'Home Manager owns the `lazy.nvim` bootstrap package'
  assert_contains "$readme_text" 'Home Manager supplies the `fff.nvim` backend from hash-pinned release assets'
  assert_contains "$readme_text" 'Windows installs Neovim and the locked raw plugin set but does not enable or install `fff.nvim`'
  assert_contains "$readme_text" 'an existing `home-manager` when available'
  assert_contains "$readme_text" '`~/dotfiles#darwin-rebuild` app'
  assert_contains "$readme_text" "### Windows Commands"
  assert_contains "$readme_text" "dotfile.ps1 [OPTIONS] [COMMAND]"
  assert_contains "$readme_text" "verify      Verify installation"
  assert_contains "$readme_text" 'NixOS flake target is `#${hostName}`'
}

test_agents_describes_windows_core_public_commands() {
  local agents_text
  agents_text="$(<"$REPO_DIR/AGENTS.md")"
  assert_contains "$agents_text" 'Windows keeps its own `verify` command'
  assert_contains "$agents_text" "existing nix-darwin or pinned nix-darwin bootstrap"
  assert_not_contains "$agents_text" "Same subcommand structure"
}

test_dry_run_update_command() {
  is_windows_bash && return 0
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(bash "$DOTFILE_CMD" --dry update 2>&1)
  assert_checked_flow "$output" true
  assert_contains "$output" "Updating packages"
  for dependency in "Codex package" "Obsidian Headless" "codebase-memory" "FFF release" "Pi extension closure" "WebCord" "Anki Zoom" "FiraCode Nerd Font" "vendored agent skills" "Neovim plugins"; do
    assert_contains "$output" "Would update $dependency"
  done
  assert_contains "$output" "Would run full dependency checks before activation"
  assert_not_contains "$output" "language toolchains"
}

test_dry_run_update_ai_command_only_updates_ai() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=arch\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry update ai 2>&1)

  assert_checked_flow "$output" true
  assert_contains "$output" "Updating AI tools and configs"
  assert_contains "$output" "Would update Codex package from the latest GitHub release"
  assert_contains "$output" "Would update Pi package from the latest npm release"
  assert_contains "$output" "Would update Pi extensions"
  assert_not_contains "$output" "Updating packages"
  assert_not_contains "$output" "fff.nvim"
}

test_dry_run_codex_command_updates_release_pin_only() {
  is_windows_bash && return 0

  local output
  output=$(bash "$DOTFILE_CMD" --dry codex 2>&1)

  assert_contains "$output" "Updating pinned Codex release package"
  assert_contains "$output" "Would update Codex package from the latest GitHub release"
  assert_not_contains "$output" "Verifying symlinks"
  assert_not_contains "$output" "Updating packages"
}

test_dry_run_lix_installer_command_updates_checksums_only() {
  is_windows_bash && return 0

  local output
  output=$(bash "$DOTFILE_CMD" --dry lix-installer 2>&1)

  assert_contains "$output" "Updating pinned Lix installer checksums"
  assert_contains "$output" "Would update Lix installer checksums"
  assert_not_contains "$output" "Verifying symlinks"
  assert_not_contains "$output" "Updating packages"
}

test_lix_installer_rejects_extra_arguments() {
  local output status=0
  output=$(bash "$DOTFILE_CMD" --dry lix-installer typo 2>&1) || status=$?

  assert_equals "1" "$status"
  assert_contains "$output" "Unexpected lix-installer argument: typo"
}

test_dry_run_obsidian_headless_command_updates_release_pin_only() {
  is_windows_bash && return 0

  local output
  output=$(bash "$DOTFILE_CMD" --dry obsidian-headless 2>&1)

  assert_contains "$output" "Updating pinned Obsidian Headless package"
  assert_contains "$output" "Would update Obsidian Headless package from the latest npm release"
  assert_not_contains "$output" "Verifying symlinks"
  assert_not_contains "$output" "Updating packages"
}

test_update_reexecutes_after_pull_with_original_flags() {
  local root="$TEST_HOME/reexec" bin="$TEST_HOME/bin" calls="$TEST_HOME/calls"
  mkdir -p "$root/scripts" "$bin"
  cp "$DOTFILE_CMD" "$root/dotfile"
  chmod +x "$root/dotfile"
  printf 'calls=%s\n' "$calls" > "$root/state"
  cat > "$root/scripts/utils.sh" <<'EOF'
info() { :; }
success() { :; }
fail() { printf '%s\n' "$*" >&2; return 1; }
doctor() { :; }
EOF
  for module in platform.sh releases.sh pins.sh doctor.sh obsidian.sh; do
    printf ':\n' > "$root/scripts/$module"
  done
  cat > "$root/scripts/packages.sh" <<'EOF'
update_packages() { printf 'old\n' >> "$DOTFILES_DIR/operation"; }
EOF
  cat > "$root/scripts/releases.sh" <<'EOF'
_dependency_update_pending() { return 1; }
_require_clean_dependency_tree() { :; }
EOF
  cat > "$bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOTFILES_DIR/git.calls"
if [[ "$*" == *"pull --rebase --autostash"* ]]; then
  cat > "$DOTFILES_DIR/scripts/packages.sh" <<'SCRIPT'
update_packages() { printf 'fresh:%s:%s\n' "$FORCE" "$QUIET" >> "$DOTFILES_DIR/operation"; }
SCRIPT
fi
EOF
  chmod +x "$bin/git"
  local output status=0
  output=$(DOTFILE_REEXEC=false DOTFILES_DIR="$root" PATH="$bin:$PATH" bash "$DOTFILE_CMD" --force --quiet update 2>&1) || status=$?
  if [[ "$status" != 0 ]]; then printf 'reexec output: %s\n' "$output" >> "$ERROR_FILE"; fi
  assert_equals "0" "$status"
  assert_equals "1" "$(grep -c 'pull --rebase --autostash' "$root/git.calls" 2>/dev/null || true)"
  assert_equals 'fresh:true:true' "$(<"$root/operation")"
}

test_update_does_not_pull_dirty_repository() {
  local root="$TEST_HOME/dirty" bin="$TEST_HOME/bin-dirty"
  mkdir -p "$root/scripts" "$bin"
  for module in utils.sh platform.sh packages.sh releases.sh pins.sh doctor.sh obsidian.sh; do
    printf ':\n' > "$root/scripts/$module"
  done
  cat > "$root/scripts/utils.sh" <<'EOF'
info() { :; }
success() { :; }
fail() { printf '%s\n' "$*" >&2; return 1; }
doctor() { :; }
EOF
  cat > "$root/scripts/releases.sh" <<'EOF'
_dependency_update_pending() { return 1; }
_require_clean_dependency_tree() { return 1; }
EOF
  printf 'update_packages() { :; }\n' > "$root/scripts/packages.sh"
  printf '#!/usr/bin/env bash\nprintf pulled > "$DOTFILES_DIR/pulled"\n' > "$bin/git"
  chmod +x "$bin/git"
  local output status=0
  output=$(DOTFILES_DIR="$root" PATH="$bin:$PATH" bash "$DOTFILE_CMD" update 2>&1) || status=$?
  assert_equals "1" "$status"
  assert_not_contains "$output" 'pulled'
  if [[ -e "$root/pulled" ]]; then
    echo "  dirty update unexpectedly called git pull" >> "$ERROR_FILE"
  fi
}

test_update_runs_doctor_before_package_update() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  printf 'local shell edits\n' > "$HOME/.zshrc"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry update 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" ".zshrc exists but is not a symlink"
  assert_not_contains "$output" "Updating dotfiles repo"
  assert_not_contains "$output" "Updating packages"
}

test_packages_allows_fresh_home_before_package_install() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Installing packages"
  assert_contains "$output" ".zshrc not found"
}

test_packages_nixos_dry() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  assert_checked_flow "$output" false 1
  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "Updating packages"

  # Don't leak the uname mock into later tests in this file.
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_readme_nixos_fresh_install_does_not_sudo_dotfile_script() {
  local readme_text
  readme_text="$(<"$REPO_DIR/README.md")"
  assert_not_contains "$readme_text" "sudo bash ./dotfile packages"
  assert_not_contains "$readme_text" "sudo bash ./dotfile all"
  assert_not_contains "$readme_text" 'bash ./dotfile packages` then `bash ./dotfile all'
  assert_not_contains "$readme_text" "Then `bash ./dotfile all`"
}

test_help_flags_exit_zero() {
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -f -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -q -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -f -q -h
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --force --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --quiet --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --help
}

test_update_ai_rejects_extra_arguments() {
  local output exit_code=0
  output=$(bash "$DOTFILE_CMD" update ai extra 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unexpected update argument: extra"
  assert_not_contains "$output" "Verifying symlinks"
}

test_explicit_all_rejects_extra_arguments() {
  local output exit_code=0
  output=$(bash "$DOTFILE_CMD" --dry all extra 2>&1) || exit_code=$?
  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unexpected all argument: extra"
}

test_leaf_commands_reject_extra_arguments() {
  local command output exit_code
  for command in all packages obsidian codex obsidian-headless; do
    output=$(bash "$DOTFILE_CMD" --dry "$command" extra 2>&1) || exit_code=$?
    assert_equals "1" "$exit_code"
    assert_contains "$output" "Unexpected $command argument: extra"
    exit_code=0
  done
  output=$(bash "$DOTFILE_CMD" --dry doctor --fast extra 2>&1) || exit_code=$?
  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unexpected doctor argument: extra"
}

test_pending_dependency_marker_blocks_all_and_packages() {
  local repo="$TEST_HOME/pending-repo"
  cp -a "$REPO_DIR/." "$repo"
  rm -rf "$repo/.git"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git -C "$repo" add -A && git -C "$repo" commit -qm baseline
  printf pending > "$repo/.git/dotfile-dependency-update"
  printf dirty > "$repo/pending.txt"
  local command output status
  for command in all packages; do
    status=0
    output="$(DOTFILES_DIR="$repo" bash "$repo/dotfile" "$command" 2>&1)" || status=$?
    assert_equals "1" "$status"
    assert_contains "$output" "Pending dependency update"
    assert_not_contains "$output" "Installing packages"
  done
}

test_update_uses_fast_doctor_preflight() {
  local dotfile_text
  dotfile_text="$(<"$DOTFILE_CMD")"
  assert_contains "$dotfile_text" 'run_checked_flow true true update_packages'
  assert_contains "$dotfile_text" 'DOTFILE_DOCTOR_SKIP_NIX_EVAL=true DOTFILE_DOCTOR_SKIP_NEOVIM_RUNTIME=true doctor'
}

test_unknown_command_fails() {
  assert_exit_code 1 bash "$DOTFILE_CMD" nonsense_command
}
