#!/usr/bin/env bash
# Neovim and fff.nvim setup tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_pi_terminal_preserves_submit_behavior() {
  local module output
  module="$REPO_DIR/config/shared/config/nvim/lua/config/pi-terminal.lua"
  assert_file_exists "$module"
  output="$(PI_TERMINAL_MODULE="$module" nvim --headless -u NONE -l "$REPO_DIR/tests/nvim/pi_terminal.lua" 2>&1)"
  assert_contains "$output" "PI_TERMINAL_OK"
}

test_raw_neovim_root_detection() {
  local module output
  module="$REPO_DIR/config/shared/config/nvim/lua/config/root.lua"
  assert_file_exists "$module"
  output="$(ROOT_MODULE="$module" nvim --headless -u NONE -l "$REPO_DIR/tests/nvim/root.lua" 2>&1)"
  assert_contains "$output" "ROOT_OK"
}

test_neovim_provisions_nix_linter() {
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "statix"
}

test_neovim_owns_only_used_build_and_mason_tools() {
  local config home
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  home="$(<"$REPO_DIR/config/home.nix")"

  assert_not_contains "$config" '"shellcheck", "shfmt"'
  assert_not_contains "$home" "lua5_1"
  assert_not_contains "$home" "luarocks"
  assert_contains "$home" "tree-sitter"
  assert_contains "$home" "unzip"
}

test_neovim_uses_raw_config() {
  local config home
  config="$REPO_DIR/config/shared/config/nvim"
  home="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$(<"$config/init.lua")" "vim.g.raw_neovim = true"
  assert_not_contains "$(<"$config/init.lua")" "LazyVim/LazyVim"
  assert_not_contains "$(<"$config/init.lua")" "markdown-toc"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.autocmds"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.commands"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.highlights"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.man"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.command_history"
  assert_not_contains "$(<"$config/init.lua")" "Snacks.picker.search_history"
  assert_not_contains "$(<"$config/lazy-lock.json")" '"LazyVim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"neotest"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"dial.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"flash.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"friendly-snippets"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"mini.ai"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"mini.hipatterns"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"grug-far.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"lazydev.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"mason-lspconfig.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"noice.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"nui.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"nvim-ts-autotag"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"persistence.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"render-markdown.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"ts-comments.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"yanky.nvim"'
  assert_contains "$(<"$config/init.lua")" 'version = "1.*"'
  assert_not_contains "$home" "seedLazyVimConfig"
  if [ -e "$config/lazyvim.json" ]; then
    printf "  legacy lazyvim.json still exists\n" >> "$ERROR_FILE"
  fi
  assert_contains "$(<"$REPO_DIR/docs/raw-neovim-evaluation.md")" "Neotest remains absent because baseline had zero adapters"
}

test_neovim_uses_reviewed_plugin_lock() {
  local config lazy lock updater
  config="$(<"$REPO_DIR/config/home.nix")"
  lazy="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  lock="$REPO_DIR/config/shared/config/nvim/lazy-lock.json"
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_contains "$config" "home.activation.seedLazyLock"
  assert_contains "$lazy" 'lazy-lock.json'
  assert_contains "$lazy" 'git", "-C", lazypath, "checkout", "--force", commit'
  assert_not_contains "$lazy" '"--branch=stable"'
  assert_equals "$(jq -r .commit "$REPO_DIR/packages/fff-release.json")" "$(jq -r '."fff.nvim".commit' "$lock")"
  assert_contains "$lazy" "version = \"v$(jq -r .version "$REPO_DIR/packages/fff-release.json")\""
  assert_contains "$updater" '"XDG_CONFIG_HOME"'
  assert_contains "$updater" '"XDG_DATA_HOME"'
  assert_contains "$updater" 'repo / "config/shared/config/nvim/init.lua"'
  assert_not_contains "$updater" 'config/shared/config/nvim/lua/plugins/fff.lua'
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

  assert_contains "$(<"$calls")" '--headless +Lazy! restore fff.nvim +qa'
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
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" 'enabled = vim.fn.has("win32") ~= 1'
}

test_fff_nvim_uses_hash_pinned_nix_backend() {
  local home package flake config
  home="$(<"$REPO_DIR/config/home.nix")"
  package="$(<"$REPO_DIR/packages/fff-nvim-backend.nix")"
  flake="$(<"$REPO_DIR/flake.nix")"
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

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

test_raw_neovim_headless_config() {
  local data lazy output
  data="$(mktemp -d)"
  lazy="${LAZY_NVIM_PATH:-$ORIG_HOME/.local/share/nvim/lazy/lazy.nvim}"
  mkdir -p "$data/config" "$data/data/nvim/lazy"
  cp -R "$REPO_DIR/config/shared/config/nvim" "$data/config/nvim"
  ln -s "$lazy" "$data/data/nvim/lazy/lazy.nvim"
  output="$(XDG_CONFIG_HOME="$data/config" XDG_DATA_HOME="$data/data" \
    FFF_FRECENCY_DB="$data/fff-frecency" FFF_HISTORY_DB="$data/fff-history" \
    nvim --headless -c "lua dofile('$REPO_DIR/tests/nvim/raw_config.lua')" +qa 2>&1)"
  assert_contains "$output" "RAW_CONFIG_OK"
  rm -rf "$data"
}

test_nix_managed_lazy_nvim_is_excluded_from_lazy_updates() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" '{ "folke/lazy.nvim", enabled = vim.fn.has("win32") == 1 }'
}
