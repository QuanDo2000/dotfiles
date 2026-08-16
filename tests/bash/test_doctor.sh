#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  unset -f command 2>/dev/null || true
  source_scripts utils.sh releases.sh doctor.sh
}

teardown() {
  cleanup_test_env
}

setup_neovim_health_fixture() {
  local config="$DOTFILES_DIR/config/shared/config/nvim" runtime="$HOME/.config/nvim"
  local plugin="$HOME/.local/share/nvim/lazy/sample.nvim"
  mkdir -p "$config/lua/config" "$runtime/lua/config" "$plugin"
  printf 'print("tracked")\n' > "$config/init.lua"
  printf 'return {}\n' > "$config/lua/config/sync.lua"
  cp "$config/lua/config/sync.lua" "$runtime/lua/config/sync.lua"
  printf 'vim.g.loaded_node_provider=0;vim.g.loaded_perl_provider=0;vim.g.loaded_ruby_provider=0;vim.g.loaded_python3_provider=0\n' > "$runtime/init.lua"
  cat "$config/init.lua" >> "$runtime/init.lua"
  git -C "$plugin" init -q
  git -C "$plugin" config user.email test@example.com
  git -C "$plugin" config user.name Test
  printf 'one\n' > "$plugin/file"
  git -C "$plugin" add file
  git -C "$plugin" commit -qm one
  local commit
  commit="$(git -C "$plugin" rev-parse HEAD)"
  jq -n --arg commit "$commit" '{"sample.nvim": {branch: "main", commit: $commit}}' > "$config/lazy-lock.json"
  cp "$config/lazy-lock.json" "$runtime/lazy-lock.json"
}

link_valid_core_dotfiles() {
  with_nix_agent_tools
  local root="${1:-$DOTFILES_DIR}"
  mkdir -p "$HOME/.config/tmux" "$HOME/.config/git" "$HOME/.config/nvim" "$HOME/.config/systemd/user" "$HOME/.codex" "$HOME/.pi/agent"
  local store_target="" candidate
  if [[ "$root" == /nix/store/* ]]; then
    for candidate in /nix/store/*; do
      [[ -e "$candidate" ]] || continue
      store_target="$candidate"
      break
    done
  else
    mkdir -p "$root/.config/nvim" "$root/.config/systemd/user" "$root/bin"
    touch "$root/.zshrc" "$root/.tmux.conf" "$root/.gitconfig" "$root/.config/nvim/init.lua" "$root/.config/nvim/fff-nvim-backend" "$root/.config/systemd/user/obsidian-sync.service" "$root/bin/dotfile"
  fi
  ln -s "${store_target:-$root/.zshrc}" "$HOME/.zshrc"
  ln -s "${store_target:-$root/.tmux.conf}" "$HOME/.config/tmux/tmux.conf"
  ln -s "${store_target:-$root/.gitconfig}" "$HOME/.config/git/config"
  ln -s "${store_target:-$root/.config/nvim/init.lua}" "$HOME/.config/nvim/init.lua"
  ln -s "${store_target:-$root/.config/nvim/fff-nvim-backend}" "$HOME/.config/nvim/fff-nvim-backend"
  ln -s "${store_target:-$root/.config/systemd/user/obsidian-sync.service}" "$HOME/.config/systemd/user/obsidian-sync.service"
  ln -s "${store_target:-$root/bin/dotfile}" "$HOME/.local/bin/dotfile"
  : > "$HOME/.codex/config.toml"
  : > "$HOME/.pi/agent/settings.json"
  : > "$HOME/.pi/agent/mcp.json"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/fff-mcp-agent"
  chmod +x "$HOME/.local/bin/fff-mcp-agent"
}

test_doctor_recovers_interrupted_release_transaction() {
  mkdir -p "$DOTFILES_DIR/packages/.pi-update.transaction"
  printf 'new package\n' > "$DOTFILES_DIR/packages/pi-agent.nix"
  printf 'new lock\n' > "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  printf '99999999|dead\n' > "$DOTFILES_DIR/packages/.pi-update.transaction/pid"
  printf 'prepared\n' > "$DOTFILES_DIR/packages/.pi-update.transaction/state"
  printf 'old package\n' > "$DOTFILES_DIR/packages/.pi-update.transaction/package.backup"
  printf 'old lock\n' > "$DOTFILES_DIR/packages/.pi-update.transaction/lock.backup"

  local output
  output="$(_check_release_transactions 2>&1)"

  assert_contains "$output" "Recovered interrupted Pi package update"
  assert_equals "old package" "$(<"$DOTFILES_DIR/packages/pi-agent.nix")"
  assert_equals "old lock" "$(<"$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json")"
}

test_doctor_recovers_orphaned_release_journal_without_fixed_lock() {
  local transaction="$DOTFILES_DIR/packages/.pi-update.transaction"
  local claim="$transaction.claim.old"
  local journal="$claim.journal"
  local owner_dir="$transaction.owner.old"
  mkdir -p "$owner_dir"
  printf 'new package\n' > "$DOTFILES_DIR/packages/pi-agent.nix"
  printf 'new lock\n' > "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  printf '99999999|dead\n' > "$claim"
  ln -s "$(basename "$owner_dir")" "$journal"
  printf 'prepared\n' > "$journal/state"
  printf 'old package\n' > "$journal/package.backup"
  printf 'old lock\n' > "$journal/lock.backup"

  local output
  output="$(_check_release_transactions 2>&1)"

  assert_contains "$output" "Recovered interrupted Pi package update"
  assert_equals "old package" "$(<"$DOTFILES_DIR/packages/pi-agent.nix")"
  assert_equals "old lock" "$(<"$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json")"
  if [[ -e "$claim" || -e "$journal" || -e "$owner_dir" ]]; then
    echo "  FAILED: doctor should clear orphaned release journal" >> "$ERROR_FILE"
  fi
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

test_doctor_finds_managed_fff_without_session_path() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/fff-mcp-agent"
  chmod +x "$HOME/.local/bin/fff-mcp-agent"
  command() { return 1; }
  errors=0
  _check_managed_commands
  assert_equals "4" "$errors"
  unset -f command
}

test_doctor_accepts_equivalent_physical_symlink_paths() {
  local original_dotfiles="$DOTFILES_DIR" physical="$TEST_TMPDIR/physical" alias="$TEST_TMPDIR/alias"
  mkdir -p "$physical/repo/config" "$HOME/.config" "$HOME/.local/bin"
  touch "$physical/repo/config/tool" "$physical/repo/dotfile"
  ln -s "$physical" "$alias"
  ln -s "$alias/repo/config/tool" "$HOME/.config/tool"
  ln -s "$alias/repo/dotfile" "$HOME/.local/bin/dotfile"
  DOTFILES_DIR="$physical/repo"
  errors=0

  _check_symlink .config/tool debian
  _check_symlink .local/bin/dotfile debian "$DOTFILES_DIR/dotfile"

  assert_equals "0" "$errors"
  DOTFILES_DIR="$original_dotfiles"
}

test_doctor_rejects_dangling_managed_links() {
  mkdir -p "$DOTFILES_DIR" "$HOME/.config/tmux"
  ln -s "$DOTFILES_DIR/missing" "$HOME/.config/tmux/tmux.conf"
  errors=0
  _check_symlink .config/tmux/tmux.conf debian
  assert_equals "1" "$errors"
}

test_doctor_fails_missing_runtime_health() {
  errors=0
  _check_writable_file .missing-runtime-file
  assert_equals "1" "$errors"
  command() { return 1; }
  _check_managed_commands
  assert_equals "6" "$errors"
  unset -f command
}

test_doctor_accepts_current_neovim_runtime() {
  setup_neovim_health_fixture
  errors=0

  _check_neovim_runtime

  assert_equals "0" "$errors"
}

test_doctor_accepts_lazy_generated_help_tags() {
  setup_neovim_health_fixture
  mkdir -p "$HOME/.local/share/nvim/lazy/sample.nvim/doc"
  printf 'generated\n' > "$HOME/.local/share/nvim/lazy/sample.nvim/doc/tags"
  errors=0

  _check_neovim_runtime

  assert_equals "0" "$errors"
}

test_doctor_reports_untracked_neovim_plugin_file() {
  setup_neovim_health_fixture
  printf 'unexpected\n' > "$HOME/.local/share/nvim/lazy/sample.nvim/untracked"
  errors=0
  local output_file="$TEST_TMPDIR/neovim-plugin-untracked-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "sample.nvim worktree differs"
}

test_doctor_reports_generated_neovim_config_drift() {
  setup_neovim_health_fixture
  printf 'print("stale")\n' >> "$HOME/.config/nvim/init.lua"
  errors=0
  local output_file="$TEST_TMPDIR/neovim-config-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "Neovim config differs"
}

test_doctor_reports_generated_neovim_lua_drift() {
  setup_neovim_health_fixture
  printf 'return { stale = true }\n' > "$HOME/.config/nvim/lua/config/sync.lua"
  errors=0
  local output_file="$TEST_TMPDIR/neovim-lua-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "Neovim Lua config differs"
}

test_doctor_reports_neovim_lock_drift() {
  setup_neovim_health_fixture
  jq '."sample.nvim".commit = "deadbeef"' "$HOME/.config/nvim/lazy-lock.json" > "$TEST_TMPDIR/runtime-lock.json"
  mv "$TEST_TMPDIR/runtime-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  errors=0
  local output_file="$TEST_TMPDIR/neovim-lock-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "Neovim lock differs"
}

test_doctor_reports_neovim_plugin_commit_drift() {
  setup_neovim_health_fixture
  local plugin="$HOME/.local/share/nvim/lazy/sample.nvim"
  printf 'two\n' > "$plugin/file"
  git -C "$plugin" commit -qam two
  errors=0
  local output_file="$TEST_TMPDIR/neovim-plugin-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "sample.nvim commit differs"
}

test_doctor_checks_managed_runtime_health() {
  local doctor_text
  doctor_text="$(<"$REPO_DIR/scripts/doctor.sh")"
  assert_contains "$doctor_text" '_check_symlink .config/tmux/tmux.conf'
  assert_contains "$doctor_text" '_check_symlink .config/git/config'
  assert_contains "$doctor_text" '.config/nvim/init.lua'
  assert_contains "$doctor_text" '.codex/config.toml'
  assert_contains "$doctor_text" '.pi/agent/settings.json'
  assert_contains "$doctor_text" 'obsidian-sync.service'
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

test_doctor_rejects_prefix_sibling_checkout() {
  mkdir -p "$DOTFILES_DIR" "${DOTFILES_DIR}-old"
  echo "content" > "${DOTFILES_DIR}-old/.zshrc"
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"
  ln -s "${DOTFILES_DIR}-old/.zshrc" "$HOME/.zshrc"
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"

  local output
  output=$(doctor 2>&1) || true

  assert_contains "$output" "expected"
  assert_not_contains "$output" "All checks passed"
}

test_doctor_reports_neovim_plugin_worktree_drift() {
  setup_neovim_health_fixture
  printf 'dirty\n' >> "$HOME/.local/share/nvim/lazy/sample.nvim/file"
  errors=0
  local output_file="$TEST_TMPDIR/neovim-plugin-worktree-doctor.log" output
  _check_neovim_runtime > "$output_file" 2>&1
  output="$(<"$output_file")"

  assert_equals "1" "$errors"
  assert_contains "$output" "sample.nvim worktree differs"
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
  mkdir -p "$HOME/.config/nvim" "$HOME/.codex" "$HOME/.pi/agent"
  mkdir -p "$HOME/.config/tmux" "$HOME/.config/git" "$HOME/.config/systemd/user"
  for path in .config/tmux/tmux.conf .config/git/config .config/nvim/init.lua .config/nvim/fff-nvim-backend .config/systemd/user/obsidian-sync.service; do
    mkdir -p "$DOTFILES_DIR/$(dirname "$path")"
    : > "$DOTFILES_DIR/$path"
    ln -s "$DOTFILES_DIR/$path" "$HOME/$path"
  done
  : > "$HOME/.codex/config.toml"
  : > "$HOME/.pi/agent/settings.json"
  : > "$HOME/.pi/agent/mcp.json"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/fff-mcp-agent"
  chmod +x "$HOME/.local/bin/fff-mcp-agent"
  with_nix_agent_tools

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

test_doctor_checks_arch_server_configuration() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release" calls="$TEST_TMPDIR/nix-calls.log"
  printf 'ID=arch\n' > "$os_release"
  mkdir -p "$DOTFILES_DIR/config"
  printf '{ username = "quando"; hostName = "nixos"; }\n' > "$DOTFILES_DIR/config/host.nix"
  touch "$DOTFILES_DIR/flake.nix"
  link_valid_core_dotfiles "/nix/store/test-home-manager-files"

  nix() {
    if [[ "$*" == *"--file"* ]]; then
      case "${@: -1}" in
        username) printf 'quando\n' ;;
        hostName) printf 'nixos\n' ;;
      esac
      return 0
    fi
    printf '%s\n' "$*" >> "$calls"
    printf '/nix/store/test-home.drv\n'
  }
  export -f nix

  OS_RELEASE="$os_release" doctor >/dev/null 2>&1

  assert_contains "$(<"$calls")" 'homeConfigurations."quando@arch-server".activationPackage.drvPath'
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
  output=$(unset XDG_CACHE_HOME; OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "All checks passed"
  assert_contains "$(tail -n 1 "$calls")" "dotfile-nix-cache."
}

test_doctor_reads_host_config_when_nix_file_eval_is_unavailable() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$os_release"
  mkdir -p "$DOTFILES_DIR/config"
  printf '{ username = "quando"; hostName = "fallbackhost"; }\n' > "$DOTFILES_DIR/config/host.nix"
  touch "$DOTFILES_DIR/flake.nix"
  link_valid_core_dotfiles "/nix/store/test-home-files"

  nix() {
    if [[ "$*" == *"--file"* ]]; then
      return 127
    fi
    printf '/nix/store/test-system.drv\n'
  }
  export -f nix

  local output
  output=$(OS_RELEASE="$os_release" doctor 2>&1)

  assert_contains "$output" "NixOS configuration fallbackhost evaluates"
  assert_contains "$output" "All checks passed"
}
