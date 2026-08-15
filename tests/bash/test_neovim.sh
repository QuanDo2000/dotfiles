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

test_neovim_explicit_sync_fails_closed() {
  local module output
  module="$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua"
  assert_file_exists "$module"
  output="$(NVIM_SYNC_MODULE="$module" nvim --headless -u NONE -l "$REPO_DIR/tests/nvim/sync.lua" 2>&1)"
  assert_contains "$output" "NVIM_SYNC_OK"
}

test_neovim_provisions_nix_linter() {
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "statix"
}

test_neovim_provisions_configured_formatters() {
  local tools
  tools="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua")"
  assert_contains "$tools" '"prettier"'
  assert_contains "$tools" '"nixfmt"'
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
  assert_not_contains "$(<"$config/init.lua")" 'render-markdown.nvim'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"ts-comments.nvim"'
  assert_not_contains "$(<"$config/lazy-lock.json")" '"yanky.nvim"'
  assert_contains "$(<"$config/init.lua")" 'version = "1.*"'
  assert_not_contains "$home" "seedLazyVimConfig"
  if [ -e "$config/lazyvim.json" ]; then
    printf "  legacy lazyvim.json still exists\n" >> "$ERROR_FILE"
  fi
}

test_neovim_sync_defers_eager_plugins_until_installed() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_equals "2" "$(grep -c 'lazy = vim.env.DOTFILE_NVIM_SYNC == "1"' <<< "$config")"
  assert_contains "$config" 'concurrency = os.getenv("DOTFILE_NVIM_SYNC") == "1" and 2 or nil'
  assert_contains "$config" 'git = { timeout = os.getenv("DOTFILE_NVIM_SYNC") == "1" and 600 or 120 }'
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

test_install_packages_syncs_neovim() {
  local calls="$TEST_TMPDIR/calls.log"
  detect_platform() { printf 'nixos\n'; }
  install_nixos() { :; }
  set_zsh_default() { :; }
  _sync_neovim() { printf 'neovim-sync\n' >> "$calls"; }

  install_packages >/dev/null

  assert_equals "neovim-sync" "$(<"$calls")"
}

test_update_packages_syncs_neovim() {
  local calls="$TEST_TMPDIR/calls.log"
  mkdir -p "$DOTFILES_DIR"
  git init -q "$DOTFILES_DIR"
  git -C "$DOTFILES_DIR" config user.email test@example.com
  git -C "$DOTFILES_DIR" config user.name Test
  : > "$DOTFILES_DIR/.test-root"
  git -C "$DOTFILES_DIR" add .test-root
  git -C "$DOTFILES_DIR" commit -qm initial
  detect_platform() { printf 'nixos\n'; }
  _update_flake_inputs() { :; }
  _update_all_dependency_pins() { :; }
  _validate_dependency_update() { :; }
  _nixos_rebuild_switch() { :; }
  _codex_version() { :; }
  _cleanup_codex_runtime_after_update() { :; }
  _update_pi_extensions() { :; }
  _sync_neovim() { printf 'neovim-sync\n' >> "$calls"; }

  update_packages >/dev/null

  assert_equals "neovim-sync" "$(<"$calls")"
}

test_sync_neovim_restores_all_plugins_cleans_and_verifies_tools() {
  local calls="$TEST_TMPDIR/nvim.log" source="$HOME/.config/nvim/fff-nvim-backend"
  DRY=false
  mkdir -p "$(dirname "$source")"
  touch "$source"
  nvim() {
    printf '%s\n' "$*" >> "$calls"
    mkdir -p "$HOME/.local/share/nvim/lazy/fff.nvim"
    printf 'RAW_NEOVIM_SYNC_OK\n'
  }
  nix() { printf 'nix should not run\n'; return 1; }

  _sync_neovim

  assert_contains "$(<"$calls")" "require('config.sync').plugins(true)"
  assert_contains "$(<"$calls")" "require('config.sync').tools()"
  assert_not_contains "$(<"$calls")" 'restore fff.nvim'
  unset -f nvim nix
}

test_sync_neovim_fails_without_success_marker() {
  DRY=false
  mkdir -p "$HOME/.config/nvim"
  touch "$HOME/.config/nvim/fff-nvim-backend"
  nvim() { printf 'Lazy build failed\n'; return 0; }

  assert_exit_code 1 _sync_neovim
  assert_contains "$NEOVIM_SYNC_ERROR" "Lazy build failed"
  unset -f nvim
}

test_sync_neovim_dry_run_does_not_start_neovim() {
  DRY=true
  nvim() { return 1; }

  assert_exit_code 0 _sync_neovim
  unset -f nvim
}

test_fff_nvim_is_disabled_on_windows() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" 'enabled = vim.fn.has("win32") ~= 1'
}

test_fff_nvim_uses_hash_pinned_nix_backend() {
  local home package flake config sync
  home="$(<"$REPO_DIR/config/home.nix")"
  package="$(<"$REPO_DIR/packages/fff-nvim-backend.nix")"
  flake="$(<"$REPO_DIR/flake.nix")"
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  sync="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua")"

  assert_contains "$package" 'fff-release.json'
  assert_equals "true" "$(jq -r '.backend["x86_64-linux"] | (.file | endswith(".so")) and (.sha256 | test("^[0-9a-f]{64}$")) and (.hash | startswith("sha256-"))' "$REPO_DIR/packages/fff-release.json")"
  assert_equals "true" "$(jq -r '.backend["aarch64-darwin"] | (.file | endswith(".dylib")) and (.sha256 | test("^[0-9a-f]{64}$")) and (.hash | startswith("sha256-"))' "$REPO_DIR/packages/fff-release.json")"
  assert_contains "$flake" 'packages.x86_64-linux.fff-nvim-backend'
  assert_contains "$flake" 'packages.aarch64-darwin.fff-nvim-backend'
  assert_contains "$home" 'xdg.configFile."nvim/fff-nvim-backend".source = fffNvimBinary;'
  assert_contains "$config" 'link_fff'
  assert_contains "$sync" 'fff-nvim-backend'
  assert_contains "$sync" 'fs_symlink'
  assert_contains "$sync" 'fs_rename'
  assert_not_contains "$sync" 'vim.fn.delete(target)'
  assert_not_contains "$config" 'download_or_build_binary'
  assert_not_contains "$config" 'cargo build'
}

_raw_neovim_cache_write() {
  local source="$1" cache="$2" marker="$3" tmp
  tmp="${cache}.tmp.$$"
  rm -rf "$tmp" "$cache" "$marker" "$marker.tmp.$$"
  mkdir -p "$(dirname "$cache")" "$tmp"
  cp -R "$source/." "$tmp/"
  mv "$tmp" "$cache"
  : > "$marker.tmp.$$"
  mv "$marker.tmp.$$" "$marker"
}

_raw_neovim_cache_read() {
  local cache="$1" marker="$2" target="$3"
  [[ -f "$marker" && -d "$cache" ]] || return 1
  mkdir -p "$target"
  cp -R "$cache/." "$target/"
}

test_raw_neovim_cache_round_trip_copies_plugin_tree() {
  local source="$TEST_TMPDIR/source-lazy" cache="$TEST_TMPDIR/cache/plugins" target="$TEST_TMPDIR/target-lazy"
  mkdir -p "$source/fff.nvim/lua" "$source/other.nvim"
  printf 'plugin-state\n' > "$source/fff.nvim/lua/init.lua"
  printf 'other-state\n' > "$source/other.nvim/state"
  _raw_neovim_cache_write "$source" "$cache" "$TEST_TMPDIR/cache/complete"
  _raw_neovim_cache_read "$cache" "$TEST_TMPDIR/cache/complete" "$target"
  assert_file_exists "$target/fff.nvim/lua/init.lua"
  assert_equals 'plugin-state' "$(<"$target/fff.nvim/lua/init.lua")"
  assert_file_exists "$target/other.nvim/state"
  assert_file_exists "$TEST_TMPDIR/cache/complete"
}

test_raw_neovim_headless_config() {
  local data source_lazy source_backend output missing_output status lock_hash cache_root cached_plugins marker lazy_dir lazy_package
  data="$(mktemp -d)"
  source_lazy="${LAZY_NVIM_PATH:-$ORIG_HOME/.local/share/nvim/lazy/lazy.nvim}"
  source_backend="${FFF_NVIM_BACKEND_PATH:-$ORIG_HOME/.config/nvim/fff-nvim-backend}"
  lock_hash="$(sha256sum "$REPO_DIR/config/shared/config/nvim/lazy-lock.json" | awk '{print $1}')"
  cache_root="${XDG_CACHE_HOME:-$ORIG_HOME/.cache}/dotfile/nvim/test-plugins/$lock_hash"
  cached_plugins="$cache_root/plugins"
  marker="$cache_root/complete"
  lazy_dir="$data/data/nvim/lazy"
  lazy_package="$data/data/nvim/site/pack/pins/start/lazy.nvim"
  mkdir -p "$data/config" "$lazy_dir" "$(dirname "$lazy_package")"
  cp -R "$REPO_DIR/config/shared/config/nvim" "$data/config/nvim"
  ln -s "$source_backend" "$data/config/nvim/fff-nvim-backend"

  if [[ "${DOTFILE_NEOVIM_TEST_FRESH:-false}" != true ]] && _raw_neovim_cache_read "$cached_plugins" "$marker" "$lazy_dir"; then
    :
  fi
  ln -s "$source_lazy" "$lazy_package"
  set +e
  output="$(XDG_CONFIG_HOME="$data/config" XDG_DATA_HOME="$data/data" \
    FFF_FRECENCY_DB="$data/fff-frecency" FFF_HISTORY_DB="$data/fff-history" \
    nvim --headless \
      -c "lua require('config.sync').plugins(true); print('RAW_PLUGIN_SYNC_OK')" \
      -c "lua dofile('$REPO_DIR/tests/nvim/raw_config.lua')" \
      -c "lua require('fff'); print('FFF_REQUIRE_OK')" +qa 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 && "$output" == *"RAW_PLUGIN_SYNC_OK"* && "$output" == *"FFF_REQUIRE_OK"* \
    && ! -f "$marker" && "${DOTFILE_NEOVIM_TEST_FRESH:-false}" != true ]]; then
    _raw_neovim_cache_write "$lazy_dir" "$cached_plugins" "$marker"
  fi
  assert_equals "0" "$status"
  assert_contains "$output" "RAW_PLUGIN_SYNC_OK"
  assert_contains "$output" "RAW_CONFIG_OK"
  assert_contains "$output" "FFF_REQUIRE_OK"
  assert_not_contains "$output" "Nix-managed fff.nvim backend is missing"

  rm -f "$data/config/nvim/fff-nvim-backend"
  missing_output="$(XDG_CONFIG_HOME="$data/config" XDG_DATA_HOME="$data/data" \
    FFF_FRECENCY_DB="$data/fff-frecency" FFF_HISTORY_DB="$data/fff-history" \
    nvim --headless -c "lua require('config.sync').plugins(false); print('MISSING_BACKEND_ACCEPTED')" +qa 2>&1)"
  assert_not_contains "$missing_output" "MISSING_BACKEND_ACCEPTED"
  assert_contains "$missing_output" "Nix-managed fff.nvim backend is missing"
  rm -rf "$data"
}

test_raw_neovim_cache_is_lock_keyed_and_bypassable() {
  local test_text
  test_text="$(<"$REPO_DIR/tests/bash/test_neovim.sh")"
  assert_contains "$test_text" 'DOTFILE_NEOVIM_TEST_FRESH'
  assert_contains "$test_text" 'test-plugins/$lock_hash'
  assert_contains "$test_text" 'cached_plugins="$cache_root/plugins"'
  assert_contains "$test_text" 'marker="$cache_root/complete"'
  assert_contains "$test_text" '_raw_neovim_cache_write "$lazy_dir" "$cached_plugins" "$marker"'
  assert_contains "$test_text" 'ln -s "$source_lazy" "$lazy_package"'
}

test_nix_managed_lazy_nvim_is_excluded_from_lazy_updates() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" '{ "folke/lazy.nvim", enabled = vim.fn.has("win32") == 1 }'
}
