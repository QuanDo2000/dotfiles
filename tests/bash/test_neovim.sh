#!/usr/bin/env bash
# Neovim setup tests.

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
  local module="$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua" output
  assert_file_exists "$module"
  output="$(XDG_CONFIG_HOME="$TEST_TMPDIR/config" NVIM_SYNC_MODULE="$module" \
    nvim --headless -u NONE -l "$REPO_DIR/tests/nvim/sync.lua" 2>&1)"
  assert_contains "$output" "NVIM_SYNC_OK"
}

test_neovim_dev_shell_provisions_parser_builder() {
  assert_contains "$(<"$REPO_DIR/flake.nix")" "tree-sitter"
}

test_neovim_provisions_nix_linter() {
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "statix"
}

test_nix_lint_is_clean() {
  statix check "$REPO_DIR"
}

test_neovim_provisions_native_node_for_mason_npm_packages() {
  local home
  home="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home" $'    nodejs\n'
}

test_neovim_provisions_configured_formatters() {
  local home pins
  home="$(<"$REPO_DIR/config/home.nix")"
  pins="$REPO_DIR/config/shared/config/nvim/mason-tools.json"
  assert_equals "string" "$(jq -r '.tools.prettier | type' "$pins")"
  assert_equals "null" "$(jq -r '.tools.nixfmt' "$pins")"
  assert_contains "$home" $'    nixfmt\n'
  assert_not_contains "$home" "nixfmt-rfc-style"
}

test_neovim_pins_mason_registry_and_tool_versions() {
  local home init pins sync
  home="$(<"$REPO_DIR/config/home.nix")"
  init="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  sync="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua")"
  pins="$REPO_DIR/config/shared/config/nvim/mason-tools.json"

  assert_file_exists "$pins"
  assert_equals "8" "$(jq '.tools | length' "$pins")"
  assert_equals "64" "$(jq -r '.registrySha256 | length' "$pins")"
  assert_contains "$init" 'registries = { require("config.mason").registry() }'
  assert_contains "$home" 'xdg.configFile."nvim/mason-tools.json"'
  assert_contains "$sync" 'get_installed_version() ~= version'
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
  local config="$REPO_DIR/config/shared/config/nvim" home init lock name
  home="$(<"$REPO_DIR/config/home.nix")"
  init="$(<"$config/init.lua")"
  lock="$(<"$config/lazy-lock.json")"

  assert_contains "$init" "vim.g.raw_neovim = true"
  assert_contains "$init" 'version = "1.*"'
  for name in LazyVim neotest dial.nvim flash.nvim friendly-snippets grug-far.nvim lazydev.nvim \
    mason-lspconfig.nvim mini.ai mini.hipatterns noice.nvim nui.nvim nvim-ts-autotag persistence.nvim \
    render-markdown.nvim trouble.nvim ts-comments.nvim yanky.nvim; do
    assert_not_contains "$lock" "\"$name\""
  done
  for name in LazyVim/LazyVim markdown-toc render-markdown.nvim Snacks.picker.autocmds \
    Snacks.picker.commands Snacks.picker.highlights Snacks.picker.man \
    Snacks.picker.command_history Snacks.picker.search_history; do
    assert_not_contains "$init" "$name"
  done
  assert_not_contains "$home" "seedLazyVimConfig"
  if [ -e "$config/lazyvim.json" ]; then
    printf "  legacy lazyvim.json still exists\n" >> "$ERROR_FILE"
  fi
}

test_neovim_sync_defers_eager_plugins_until_installed() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_equals "3" "$(grep -c 'lazy = vim.env.DOTFILE_NVIM_SYNC == "1"' <<< "$config")"
  assert_contains "$config" 'concurrency = os.getenv("DOTFILE_NVIM_SYNC") == "1" and 2 or nil'
  assert_contains "$(<"$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua")" 'options.git.timeout = 600'
}

test_neovim_uses_reviewed_plugin_lock() {
  local config lazy lock updater
  config="$(<"$REPO_DIR/config/home.nix")"
  lazy="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  lock="$REPO_DIR/config/shared/config/nvim/lazy-lock.json"
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_contains "$config" "home.activation.seedLazyLock"
  assert_contains "$config" 'if ! managed_file_current "${./shared/config/nvim/lazy-lock.json}" "$target"; then'
  assert_contains "$lazy" 'lazy-lock.json'
  assert_contains "$lazy" 'git", "-C", lazypath, "checkout", "--force", commit'
  assert_not_contains "$lazy" '"--branch=stable"'
  assert_equals "false" "$(jq 'has("fff.nvim")' "$lock")"
  assert_not_contains "$lazy" 'dmtrKovalenko/fff.nvim'
  assert_contains "$updater" '"XDG_CONFIG_HOME"'
  assert_contains "$updater" '"XDG_DATA_HOME"'
  assert_contains "$updater" 'repo / "config/shared/config/nvim"'
  assert_not_contains "$updater" 'config/shared/config/nvim/lua/plugins/fff.lua'
  assert_not_contains "$updater" 'fff.nvim'
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
  DRY=true
  detect_platform() { printf 'nixos\n'; }
  _refresh_all_dependency_set() { :; }
  _validate_dependency_update() { :; }
  _approve_dependency_update() { :; }
  _nixos_rebuild_switch() { :; }
  _codex_version() { :; }
  _cleanup_codex_runtime_after_update() { :; }
  _update_pi_extensions() { :; }
  _sync_neovim() { printf 'neovim-sync\n' >> "$calls"; }
  _publish_dependency_update() { printf 'published\n' >> "$calls"; }
  _finish_dependency_update() { :; }

  update_packages >/dev/null

  assert_equals $'neovim-sync\npublished' "$(<"$calls")"
}

test_sync_neovim_skips_full_restore_when_runtime_is_current() {
  local calls="$TEST_TMPDIR/nvim.log"
  DRY=false
  DOTFILE_NVIM_SYNC=1
  nvim() {
    printf '%s:%s\n' "${DOTFILE_NVIM_SYNC:-unset}" "$*" >> "$calls"
    printf 'RAW_NEOVIM_SYNC_CURRENT\n'
  }

  _sync_neovim

  assert_equals "1" "$(wc -l < "$calls" | tr -d ' ')"
  assert_contains "$(<"$calls")" "0:"
  assert_contains "$(<"$calls")" "runtime_complete()"
  assert_equals "1" "$DOTFILE_NVIM_SYNC"
  assert_not_contains "$(<"$calls")" "plugins(true)"
  unset -f nvim
}

test_sync_neovim_restores_all_plugins_cleans_and_verifies_tools() {
  local calls="$TEST_TMPDIR/nvim.log"
  DRY=false
  nvim() {
    printf '%s\n' "$*" >> "$calls"
    printf 'RAW_NEOVIM_SYNC_OK\n'
  }
  nix() { printf 'nix should not run\n'; return 1; }

  _sync_neovim

  assert_contains "$(<"$calls")" "sync.plugins(true)"
  assert_contains "$(<"$calls")" "sync.tools()"
  assert_contains "$(<"$calls")" "sync.parsers()"
  assert_not_contains "$(<"$calls")" 'restore fff.nvim'
  unset -f nvim nix
}

test_sync_neovim_fails_without_success_marker() {
  DRY=false
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

test_neovim_loads_snacks_before_initial_buffer() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" $'"folke/snacks.nvim",\n    lazy = vim.env.DOTFILE_NVIM_SYNC == "1",'
  assert_not_contains "$config" 'event = "VimEnter"'
  assert_not_contains "$config" 'quickfile = { enabled = true }'
}

test_neovim_uses_snacks_without_fff_dependency() {
  local config lock home flake sync updater
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"
  lock="$REPO_DIR/config/shared/config/nvim/lazy-lock.json"
  home="$(<"$REPO_DIR/config/home.nix")"
  flake="$(<"$REPO_DIR/flake.nix")"
  sync="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/sync.lua")"
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_contains "$config" 'map("n", "<leader>ff", function() Snacks.picker.files({ cwd = root() }) end, "Find Files")'
  assert_contains "$config" 'map("n", "<leader>sg", function() Snacks.picker.grep({ cwd = root() }) end, "Grep")'
  assert_not_contains "$config" 'dmtrKovalenko/fff.nvim'
  assert_not_contains "$config" 'require("fff")'
  assert_equals "false" "$(jq 'has("fff.nvim")' "$lock")"
  assert_not_contains "$home" 'fff-nvim-backend'
  assert_not_contains "$flake" 'fff-nvim-backend'
  assert_not_contains "$sync" 'link_fff'
  assert_not_contains "$updater" 'fff.nvim'
  assert_equals "false" "$([[ -e "$REPO_DIR/packages/fff-nvim-backend.nix" ]] && echo true || echo false)"
}


_raw_neovim_cache_lock() {
  local lock="$1" attempts=0
  mkdir -p "$(dirname "$lock")"
  until mkdir "$lock" 2>/dev/null; do
    attempts=$((attempts + 1))
    (( attempts < 200 )) || return 1
    sleep 0.05
  done
}

_raw_neovim_cache_write() {
  local source="$1" cache="$2" marker="$3" tmp lock rc=0
  tmp="${cache}.tmp.$$"
  lock="${marker%/*}/.lock"
  _raw_neovim_cache_lock "$lock" || return 1
  if rm -rf "$tmp" "$cache" "$marker" "$marker.tmp.$$" \
    && mkdir -p "$(dirname "$cache")" "$tmp" \
    && cp -R "$source/." "$tmp/" \
    && mv "$tmp" "$cache" \
    && : > "$marker.tmp.$$" \
    && mv "$marker.tmp.$$" "$marker"; then
    rc=0
  else
    rc=$?
  fi
  rmdir "$lock" || return 1
  return "$rc"
}

_raw_neovim_cache_read() {
  local cache="$1" marker="$2" target="$3" lock rc=0
  lock="${marker%/*}/.lock"
  _raw_neovim_cache_lock "$lock" || return 1
  if [[ -f "$marker" && -d "$cache" ]] && mkdir -p "$target" && cp -R "$cache/." "$target/"; then
    rc=0
  else
    rc=1
  fi
  rmdir "$lock" || return 1
  return "$rc"
}

_raw_neovim_cache_seed() {
  local root="$1" key="$2" target="$3" current="$1/$2" old_marker
  [[ "${DOTFILE_NEOVIM_TEST_FRESH:-false}" != true ]] || return 1
  _raw_neovim_cache_read "$current/plugins" "$current/complete" "$target" && return
  for old_marker in "$root"/*/complete; do
    [[ "$old_marker" == "$current/complete" ]] && continue
    _raw_neovim_cache_read "${old_marker%/complete}/plugins" "$old_marker" "$target" && return
  done
  return 1
}

test_raw_neovim_cache_reuses_previous_lock() {
  local root="$TEST_TMPDIR/cache" target="$TEST_TMPDIR/target"
  mkdir -p "$root/old/plugins/sample.nvim"
  printf 'cached\n' > "$root/old/plugins/sample.nvim/state"
  touch "$root/old/complete"

  assert_exit_code 0 _raw_neovim_cache_seed "$root" new "$target"
  assert_equals cached "$(<"$target/sample.nvim/state")"
  DOTFILE_NEOVIM_TEST_FRESH=true assert_exit_code 1 _raw_neovim_cache_seed "$root" new "$target"
}

test_raw_neovim_cache_serializes_publication() {
  local root="$TEST_TMPDIR/cache" source="$TEST_TMPDIR/source" pid
  mkdir -p "$root/new/.lock" "$source/sample.nvim"
  printf 'cached\n' > "$source/sample.nvim/state"

  _raw_neovim_cache_write "$source" "$root/new/plugins" "$root/new/complete" &
  pid=$!
  sleep 0.1
  if [[ -e "$root/new/complete" ]]; then
    printf '  cache published while lock was held\n' >> "$ERROR_FILE"
  fi
  rmdir "$root/new/.lock"
  wait "$pid"
  assert_file_exists "$root/new/complete"
}

test_raw_neovim_headless_config() {
  is_windows_bash && return 0
  local data source_lazy output status lock_hash cache_base cache_root cached_plugins marker lazy_dir lazy_package bigfile
  data="$(mktemp -d)"
  source_lazy="${LAZY_NVIM_PATH:-$ORIG_HOME/.local/share/nvim/site/pack/hm/start/lazy.nvim}"
  lock_hash="$(sha256sum "$REPO_DIR/config/shared/config/nvim/lazy-lock.json" | awk '{print $1}')"
  cache_base="${XDG_CACHE_HOME:-$ORIG_HOME/.cache}/dotfile/nvim/test-plugins"
  cache_root="$cache_base/$lock_hash"
  cached_plugins="$cache_root/plugins"
  marker="$cache_root/complete"
  lazy_dir="$data/data/nvim/lazy"
  lazy_package="$data/data/nvim/site/pack/pins/start/lazy.nvim"
  mkdir -p "$data/config" "$lazy_dir" "$(dirname "$lazy_package")"
  cp -R "$REPO_DIR/config/shared/config/nvim" "$data/config/nvim"

  if [[ "${DOTFILE_NEOVIM_TEST_CACHE:-true}" == true ]]; then
    _raw_neovim_cache_seed "$cache_base" "$lock_hash" "$lazy_dir" || true
  fi
  ln -s "$source_lazy" "$lazy_package"
  set +e
  output="$(DOTFILE_NVIM_SYNC=1 XDG_CONFIG_HOME="$data/config" XDG_DATA_HOME="$data/data" \
    nvim --headless \
      -c "lua require('config.sync').plugins(true); print('RAW_PLUGIN_SYNC_OK')" \
      -c "lua dofile('$REPO_DIR/tests/nvim/raw_config.lua')" +qa 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 && "$output" == *"RAW_PLUGIN_SYNC_OK"* && "$output" == *"RAW_CONFIG_OK"* \
    && ! -f "$marker" && "${DOTFILE_NEOVIM_TEST_FRESH:-false}" != true \
    && "${DOTFILE_NEOVIM_TEST_CACHE:-true}" == true ]]; then
    _raw_neovim_cache_write "$lazy_dir" "$cached_plugins" "$marker"
  fi
  assert_equals "0" "$status"
  assert_contains "$output" "RAW_PLUGIN_SYNC_OK"
  assert_contains "$output" "RAW_CONFIG_OK"

  bigfile="$(cd "$data" && pwd -P)/big.lua"
  head -c 1600000 </dev/zero | tr '\0' x > "$bigfile"
  set +e
  output="$(XDG_CONFIG_HOME="$data/config" XDG_DATA_HOME="$data/data" nvim --headless "$bigfile" \
    -c "lua assert(vim.bo.filetype == 'bigfile', 'initial big file was not protected'); assert(vim.b.completion == false, 'completion remained enabled for initial big file'); print('INITIAL_BIGFILE_OK')" +qa 2>&1)"
  status=$?
  set -e
  assert_equals "0" "$status"
  assert_contains "$output" "INITIAL_BIGFILE_OK"
  rm -rf "$data"
}

test_nix_managed_lazy_nvim_is_excluded_from_lazy_updates() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$config" '{ "folke/lazy.nvim", enabled = vim.fn.has("win32") == 1 }'
}
