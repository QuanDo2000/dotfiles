#!/usr/bin/env bash
# Neovim and fff.nvim setup tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_home_manager_seeds_writable_lazyvim_config() {
  local config
  config="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$config" "home.activation.seedLazyVimConfig"
  assert_contains "$config" '${../scripts/seed_merge}/lazyvim.py'
  assert_contains "$config" "lazyvim-seed.json"
  assert_contains "$config" 'psCommand = if pkgs.stdenv.isDarwin then "/bin/ps" else "${pkgs.procps}/bin/ps";'
  assert_contains "$config" '"${psCommand}" -A -o comm='
  assert_not_contains "$config" "if /bin/ps -A"
  assert_contains "$config" "Skipping LazyVim config sync while Neovim is running"
  assert_not_contains "$config" 'xdg.configFile."nvim/lazyvim.json"'
}

test_neovim_uses_reviewed_plugin_lock() {
  local config lazy lock updater
  config="$(<"$REPO_DIR/config/home.nix")"
  lazy="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/lazy.lua")"
  lock="$REPO_DIR/config/shared/config/nvim/lazy-lock.json"
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_contains "$config" "home.activation.seedLazyLock"
  assert_contains "$lazy" 'lazy-lock.json'
  assert_contains "$lazy" 'git", "-C", lazypath, "checkout", "--force", lazy_commit'
  assert_not_contains "$lazy" '"--branch=stable"'
  assert_equals "$(jq -r .commit "$REPO_DIR/packages/fff-release.json")" "$(jq -r '."fff.nvim".commit' "$lock")"
  assert_contains "$(<"$REPO_DIR/config/shared/config/nvim/lua/plugins/fff.lua")" "version = \"v$(jq -r .version "$REPO_DIR/packages/fff-release.json")\""
  assert_contains "$updater" '"XDG_CONFIG_HOME"'
  assert_contains "$updater" '"XDG_DATA_HOME"'
  assert_contains "$updater" 'lock["fff.nvim"]["commit"] != fff["commit"]'
}

test_install_packages_syncs_fff_nvim() {
  local calls="$TEST_TMPDIR/calls.log"
  detect_platform() { printf 'nixos\n'; }
  install_nixos() { :; }
  set_zsh_default() { :; }
  _sync_fff_nvim() { printf 'fff-sync\n' >> "$calls"; }

  install_packages >/dev/null

  assert_equals "fff-sync" "$(<"$calls")"
}

test_update_packages_syncs_fff_nvim() {
  local calls="$TEST_TMPDIR/calls.log"
  detect_platform() { printf 'nixos\n'; }
  _update_flake_inputs() { :; }
  _update_all_dependency_pins() { :; }
  _validate_dependency_update() { :; }
  _nixos_rebuild_switch() { :; }
  _codex_version() { :; }
  _cleanup_codex_runtime_after_update() { :; }
  _update_pi_extensions() { :; }
  _sync_fff_nvim() { printf 'fff-sync\n' >> "$calls"; }

  update_packages >/dev/null

  assert_equals "fff-sync" "$(<"$calls")"
}

test_sync_fff_nvim_runs_headless_lazy_sync_and_links_nix_backend() {
  local calls="$TEST_TMPDIR/nvim.log"
  local source="$HOME/.config/nvim/fff-nvim-backend"
  local extension=so
  [ "$(uname -s)" = Darwin ] && extension=dylib
  local target="$HOME/.local/share/nvim/lazy/fff.nvim/target/release/libfff_nvim.$extension"
  DRY=false
  mkdir -p "$(dirname "$source")"
  touch "$source"
  nvim() {
    printf '%s\n' "$*" >> "$calls"
    mkdir -p "$HOME/.local/share/nvim/lazy/fff.nvim"
  }

  _sync_fff_nvim

  assert_contains "$(<"$calls")" '--headless +Lazy! sync fff.nvim +qa'
  assert_symlink "$target" "$source"
  unset -f nvim
}

test_sync_fff_nvim_does_not_compile_backend() {
  DRY=false
  mkdir -p "$HOME/.config/nvim"
  touch "$HOME/.config/nvim/fff-nvim-backend"
  nvim() {
    mkdir -p "$HOME/.local/share/nvim/lazy/fff.nvim"
  }
  nix() { printf 'nix should not run\n'; return 1; }

  _sync_fff_nvim

  assert_equals "" "$FFF_NVIM_WARNING"
  unset -f nvim nix
}

test_sync_fff_nvim_failure_warns_without_failing_update() {
  DRY=false
  nvim() { printf 'clone failed\n'; return 1; }

  assert_exit_code 0 _sync_fff_nvim
  assert_contains "$FFF_NVIM_WARNING" "clone failed"
  assert_contains "$(_report_fff_nvim_warning)" "WARN"
  assert_contains "$(_report_fff_nvim_warning)" "fff.nvim setup failed"
  unset -f nvim
}

test_sync_fff_nvim_dry_run_does_not_start_neovim() {
  DRY=true
  nvim() { return 1; }

  assert_exit_code 0 _sync_fff_nvim
  unset -f nvim
}

test_fff_nvim_is_disabled_on_windows() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/lua/plugins/fff.lua")"

  assert_contains "$config" 'vim.fn.has("win32") == 1'
  assert_contains "$config" "return {}"
}

test_fff_nvim_uses_hash_pinned_nix_backend() {
  local home package flake config
  home="$(<"$REPO_DIR/config/home.nix")"
  package="$(<"$REPO_DIR/packages/fff-nvim-backend.nix")"
  flake="$(<"$REPO_DIR/flake.nix")"
  config="$(<"$REPO_DIR/config/shared/config/nvim/lua/plugins/fff.lua")"

  assert_contains "$package" 'fff-release.json'
  assert_equals "true" "$(jq -r '.backend["x86_64-linux"] | (.file | endswith(".so")) and (.sha256 | test("^[0-9a-f]{64}$")) and (.hash | startswith("sha256-"))' "$REPO_DIR/packages/fff-release.json")"
  assert_equals "true" "$(jq -r '.backend["aarch64-darwin"] | (.file | endswith(".dylib")) and (.sha256 | test("^[0-9a-f]{64}$")) and (.hash | startswith("sha256-"))' "$REPO_DIR/packages/fff-release.json")"
  assert_contains "$flake" 'packages.x86_64-linux.fff-nvim-backend'
  assert_contains "$flake" 'packages.aarch64-darwin.fff-nvim-backend'
  assert_contains "$home" 'xdg.configFile."nvim/fff-nvim-backend".source = fffNvimBinary;'
  assert_contains "$config" 'fff-nvim-backend'
  assert_contains "$config" 'fs_symlink'
  assert_not_contains "$config" 'download_or_build_binary'
  assert_not_contains "$config" 'cargo build'
}

test_home_manager_lazyvim_guard_uses_runnable_ps() {
  local nix_bin
  if ! nix_bin="$(type -P nix)"; then
    return
  fi
  local activation ps_path
  if [[ "$(uname -s)" == "Darwin" ]]; then
    activation="$("$nix_bin" eval --raw "$REPO_DIR#darwinConfigurations.mac.config.home-manager.users.quando.home.activation.seedLazyVimConfig.data")"
    assert_contains "$activation" '"/bin/ps" -A -o comm='
    assert_exit_code 0 /bin/ps -A
  else
    activation="$("$nix_bin" eval --raw "$REPO_DIR#nixosConfigurations.nixos.config.home-manager.users.quando.home.activation.seedLazyVimConfig.data")"
    ps_path="$(grep -o '/nix/store/[^ "]*/bin/ps' <<< "$activation" | head -1)"
    local nix_store_bin
    nix_store_bin="$(type -P nix-store)"
    assert_exit_code 0 "$nix_store_bin" --realise "${ps_path%/bin/ps}"
    assert_file_exists "$ps_path"
    assert_exit_code 0 "$ps_path" --version
  fi
}

test_nix_managed_lazy_nvim_is_excluded_from_lazy_updates() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/lazy.lua")"

  assert_contains "$config" '{ "folke/lazy.nvim", enabled = false }'
}
