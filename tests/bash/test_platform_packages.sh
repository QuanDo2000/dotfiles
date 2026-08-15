#!/usr/bin/env bash
# Platform package installation tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

HOME_CONFIG="$(<"$REPO_DIR/config/home.nix")"
FLAKE_CONFIG="$(<"$REPO_DIR/flake.nix")"
HYPR_CONFIG="$(<"$REPO_DIR/config/unix/config/hypr/hyprland.lua")"
NIXOS_CONFIG="$(<"$REPO_DIR/config/nixos/configuration.nix")"
WAYBAR_CONFIG="$(<"$REPO_DIR/config/unix/config/waybar/config.jsonc")"
WAYBAR_STYLE="$(<"$REPO_DIR/config/unix/config/waybar/style.css")"
POWER_MENU="$(<"$REPO_DIR/config/unix/config/waybar/power-menu.xml")"
SUNSET_CONFIG="$(<"$REPO_DIR/config/unix/config/hypr/hyprsunset.conf")"
SUNSET_STATUS_SCRIPT="$(<"$REPO_DIR/scripts/hyprsunset-status.sh")"
INPUT_METHOD_STATUS_SCRIPT="$(<"$REPO_DIR/scripts/input-method-status.sh")"
SSH_CONFIG="$(<"$REPO_DIR/config/shared/.ssh/config")"

test_nvm_numeric_default_selects_matching_version() {
  local nvm_root="$TEST_TMPDIR/nvm-home" nvm_home output
  nvm_home="$nvm_root/.nvm"
  mkdir -p "$nvm_home/versions/node/v10.2.0/bin" "$nvm_home/versions/node/v10.24.1/bin" "$nvm_home/versions/node/v20.19.0/bin"
  printf 'ready\n' > "$nvm_home/nvm.sh"
  touch "$nvm_home/versions/node/v10.2.0/bin/node" "$nvm_home/versions/node/v10.24.1/bin/node" "$nvm_home/versions/node/v20.19.0/bin/node"
  chmod +x "$nvm_home/versions/node"/v*/bin/node
  mkdir -p "$nvm_home/alias"
  printf '10\n' > "$nvm_home/alias/default"
  output=$(HOME="$nvm_root" zsh -f -c 'source "$1"; print -r -- $path[1]' zsh "$REPO_DIR/config/unix/.zshrc.base")
  assert_contains ":$output:" ":$nvm_home/versions/node/v10.24.1/bin:"
  assert_not_contains "$output" "$nvm_home/versions/node/v20.19.0/bin"
}

test_nvm_numeric_default_does_not_select_unrelated_major() {
  local nvm_root="$TEST_TMPDIR/nvm-unmatched" nvm_home output
  nvm_home="$nvm_root/.nvm"
  mkdir -p "$nvm_home/versions/node/v20.19.0/bin" "$nvm_home/alias"
  printf 'ready\n' > "$nvm_home/nvm.sh"
  printf '10\n' > "$nvm_home/alias/default"
  touch "$nvm_home/versions/node/v20.19.0/bin/node"
  chmod +x "$nvm_home/versions/node/v20.19.0/bin/node"
  output=$(HOME="$nvm_root" zsh -f -c 'source "$1"; print -r -- $path[1]' zsh "$REPO_DIR/config/unix/.zshrc.base")
  assert_not_contains "$output" "$nvm_home/versions/node/v20.19.0/bin"
}

test_nvm_fallback_uses_portable_zsh_selection() {
  local zshrc
  zshrc="$(<"$REPO_DIR/config/unix/.zshrc.base")"
  assert_not_contains "$zshrc" 'sort -V'
  assert_not_contains "$zshrc" 'find "$NVM_DIR/versions/node"'
  assert_contains "$zshrc" 'NVM_DIR/versions/node/'
  assert_contains "$zshrc" 'setopt localoptions numericglobsort'
}

test_nvm_resolves_chained_alias_and_numeric_fallback() {
  local chain_home="$TEST_TMPDIR/chain-home" fallback_home="$TEST_TMPDIR/fallback-home"
  mkdir -p "$chain_home/.nvm/versions/node/v18.2.0/bin" "$chain_home/.nvm/alias"
  printf 'ready\n' > "$chain_home/.nvm/nvm.sh"
  printf 'lts\n' > "$chain_home/.nvm/alias/default"
  printf 'v18.2.0\n' > "$chain_home/.nvm/alias/lts"
  touch "$chain_home/.nvm/versions/node/v18.2.0/bin/node"
  chmod +x "$chain_home/.nvm/versions/node/v18.2.0/bin/node"
  local chained
  chained="$(HOME="$chain_home" zsh -f -c 'source "$1"; print -r -- $path[1]' zsh "$REPO_DIR/config/unix/.zshrc.base")"
  assert_equals "$chain_home/.nvm/versions/node/v18.2.0/bin" "$chained"

  mkdir -p "$fallback_home/.nvm/versions/node/v2.9.0/bin" "$fallback_home/.nvm/versions/node/v10.1.0/bin"
  printf 'ready\n' > "$fallback_home/.nvm/nvm.sh"
  touch "$fallback_home/.nvm/versions/node/v2.9.0/bin/node" "$fallback_home/.nvm/versions/node/v10.1.0/bin/node"
  chmod +x "$fallback_home/.nvm"/versions/node/*/bin/node
  local newest
  newest="$(HOME="$fallback_home" zsh -f -c 'source "$1"; print -r -- $path[1]' zsh "$REPO_DIR/config/unix/.zshrc.base")"
  assert_equals "$fallback_home/.nvm/versions/node/v10.1.0/bin" "$newest"
}

test_hyprsunset_status_uses_defaults_when_installed_config_missing() {
  local home="$TEST_TMPDIR/hypr-home"
  mkdir -p "$home/.local/bin" "$home/.config/hypr"
  ln -s "$REPO_DIR/scripts/hyprsunset-status.sh" "$home/.local/bin/hyprsunset-status"
  local output
  output="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" HYPRSUNSET_RUNNING=false "$home/.local/bin/hyprsunset-status" 12:00)"
  assert_contains "$output" 'Night light service is inactive'
  assert_not_contains "$output" 'awk:'
}

test_ssh_config_keeps_required_forwarding_without_unused_ports() {
  assert_not_contains "$SSH_CONFIG" "LocalForward"
  assert_equals "2" "$(grep -c '^[[:space:]]*ForwardX11 yes$' <<< "$SSH_CONFIG")"
  assert_equals "2" "$(grep -c '^[[:space:]]*ForwardX11Trusted yes$' <<< "$SSH_CONFIG")"
  assert_equals "3" "$(grep -c '^[[:space:]]*ForwardAgent yes$' <<< "$SSH_CONFIG")"
}

test_arch_packages_are_bootstrap_only() {
  assert_contains "${ARCH_PACKAGES[*]}" "base-devel"
  assert_contains "${ARCH_PACKAGES[*]}" "curl"
  assert_contains "${ARCH_PACKAGES[*]}" "git"
  assert_contains "${ARCH_PACKAGES[*]}" "zsh"
  for pkg in neovim starship nodejs tmux lazygit jujutsu ripgrep fd fzf; do
    if [[ " ${ARCH_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Arch pacman packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_tmux_uses_native_clipboard_bindings_without_yank_plugin() {
  local tmux_config
  tmux_config="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_not_contains "$HOME_CONFIG" 'pkgs.tmuxPlugins.yank'
  assert_contains "$tmux_config" 'set -g set-clipboard on'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi Y send-keys -X copy-selection-and-cancel \; paste-buffer -p'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel'
}

test_tmux_owns_catppuccin_theme_without_plugin() {
  local tmux_config
  tmux_config="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_not_contains "$HOME_CONFIG" 'tmuxPlugins.catppuccin'
  assert_not_contains "$tmux_config" '@catppuccin_'
  assert_contains "$tmux_config" 'set -g mode-style "bg=#363a4f,bold"'
  assert_contains "$tmux_config" 'set -g status-style "default"'
  assert_contains "$tmux_config" 'set -g menu-selected-style "fg=#cad3f5,bold,bg=#6e738d"'
  assert_contains "$tmux_config" 'set -g popup-style "bg=#24273a,fg=#cad3f5"'
  assert_contains "$tmux_config" 'set -g popup-border-style "fg=#494d64"'
  assert_contains "$tmux_config" 'set -g window-status-current-format'
  assert_contains "$tmux_config" 'set -g status-right '
  assert_contains "$tmux_config" '%Y-%m-%d %H:%M:%S'
}

test_tmux_config_parses_and_applies_theme() {
  local socket="$TEST_TMPDIR/tmux.sock" config="$HOME/.config/tmux/tmux.conf"
  local stderr="$TEST_TMPDIR/tmux.stderr" status=0
  mkdir -p "$(dirname "$config")"
  cp "$REPO_DIR/config/unix/.tmux.conf" "$config"
  _cleanup_tmux_test() {
    trap - RETURN
    env HOME="$HOME" TMUX= tmux -S "$socket" kill-server >/dev/null 2>&1 || true
  }
  trap _cleanup_tmux_test RETURN

  env HOME="$HOME" TMUX= tmux -S "$socket" -f "$config" new-session -d -s audit 'sleep 30' 2> "$stderr" || status=$?

  assert_equals "0" "$status"
  assert_equals "" "$(<"$stderr")"
  if (( status == 0 )); then
    assert_equals "fg=#cad3f5,bold,bg=#6e738d" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv menu-selected-style)"
    assert_equals "bg=#24273a,fg=#cad3f5" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv popup-style)"
    assert_equals "fg=#494d64" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv popup-border-style)"
  fi
}

test_code_search_stack_uses_current_full_feature_packages() {
  local fff codebase codebase_pins fff_pins pi_extensions
  fff="$(<"$REPO_DIR/packages/fff-mcp.nix")"
  codebase="$(<"$REPO_DIR/packages/codebase-memory-mcp.nix")"
  codebase_pins="$REPO_DIR/packages/codebase-memory-mcp-release.json"
  fff_pins="$REPO_DIR/packages/fff-release.json"
  pi_extensions="$REPO_DIR/config/shared/ai/pi/extensions/package.json"

  assert_contains "$fff" 'fff-release.json'
  assert_equals "true" "$(jq -r '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$fff_pins")"
  assert_equals "true" "$(jq -r '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$codebase_pins")"
  assert_contains "$codebase" 'codebase-memory-mcp-release.json'
  assert_contains "$codebase" '${source.file}'
  assert_contains "$codebase" 'stdenv.hostPlatform.isLinux'
  assert_not_contains "$codebase" 'stdenv.isLinux'
  assert_equals "true" "$(jq -r '.linux.amd64.file | test("^codebase-memory-mcp(-ui)?-linux-amd64.*\\.tar\\.gz$")' "$codebase_pins")"
  assert_equals "true" "$(jq -r '.windows.amd64.file | test("^codebase-memory-mcp(-ui)?-windows-amd64.*\\.zip$")' "$codebase_pins")"
  assert_equals "false" "$(jq -r '.dependencies | has("@ff-labs/pi-fff")' "$pi_extensions")"
}

test_pi_web_access_is_pinned() {
  assert_equals "true" "$(jq -r '.dependencies["pi-web-access"] | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$REPO_DIR/config/shared/ai/pi/extensions/package.json")"
}

test_pi_lsp_uses_pinned_package_and_nix_servers() {
  local lsp_config
  lsp_config="$REPO_DIR/config/shared/ai/pi/pi-lsp.json"

  assert_equals "0.49.4" "$(jq -r '.dependencies["@narumitw/pi-lsp"]' "$REPO_DIR/config/shared/ai/pi/extensions/package.json")"
  assert_file_exists "$lsp_config"
  if [[ -f "$lsp_config" ]]; then
    assert_exit_code 0 jq -e '
      .timeout == 30000 and
      .servers.vtsls.command == ["vtsls", "--stdio"] and
      .servers.nil.command == ["nil"] and
      .servers.nil.pushDiagnosticsGraceMs == 3000 and
      .servers["bash-language-server"].command == ["bash-language-server", "start"]
    ' "$lsp_config"
  fi
  for package in vtsls nil bash-language-server shellcheck; do
    assert_contains "$HOME_CONFIG" "$package"
  done
  assert_contains "$HOME_CONFIG" 'settings.json mcp.json pi-lsp.json subagent-config.json:extensions/subagent/config.json'
}

test_pi_subagents_configures_native_seven_child_limits() {
  local config
  config="$REPO_DIR/config/shared/ai/pi/subagent-config.json"

  assert_file_exists "$config"
  if [[ -f "$config" ]]; then
    assert_exit_code 0 jq -e '
      .globalConcurrencyLimit == 7 and
      .parallel.maxTasks == 7 and
      .parallel.concurrency == 7
    ' "$config"
  fi
  assert_contains "$HOME_CONFIG" 'if [ "$name" = "subagent-config.json" ]; then'
  assert_contains "$HOME_CONFIG" 'base_tmp="$(mktemp "$base.tmp.XXXXXX")"'
  assert_contains "$(<"$REPO_DIR/config/shared/ai/AGENTS.md")" 'never pass more than seven children to one workflow or overlap workflows'
}

test_code_search_stack_enables_auto_index_and_agent_workflows() {
  local codex agents nvim_fff
  codex="$(<"$REPO_DIR/config/shared/ai/codex/config.toml")"
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  nvim_fff="$(<"$REPO_DIR/config/shared/config/nvim/init.lua")"

  assert_contains "$HOME_CONFIG" 'config set auto_index true'
  assert_contains "$HOME_CONFIG" 'config set auto_watch true'
  assert_contains "$HOME_CONFIG" 'FFF_FRECENCY_DB = "${homeDir}/.local/state/fff/frecency";'
  assert_contains "$HOME_CONFIG" '".local/bin/fff-mcp-agent"'
  assert_contains "$HOME_CONFIG" 'exec "${pkgs.fff-mcp}/bin/fff-mcp"'
  assert_contains "$HOME_CONFIG" '--frecency-db'
  assert_not_contains "$HOME_CONFIG" '--history-db'
  assert_contains "$codex" 'args = ["fff-mcp-agent"]'
  assert_contains "$nvim_fff" 'frecency = { db_path = vim.env.FFF_FRECENCY_DB or vim.fn.expand("~/.local/state/fff/frecency") }'
  assert_contains "$nvim_fff" 'history = { db_path = vim.env.FFF_HISTORY_DB or vim.fn.expand("~/.local/state/fff/history") }'
  assert_contains "$codex" '[mcp_servers.fff.tools.find_files]'
  assert_contains "$codex" '[mcp_servers.fff.tools.grep]'
  assert_contains "$codex" '[mcp_servers.fff.tools.multi_grep]'
  assert_contains "$codex" '[mcp_servers.codebase-memory-mcp.tools.detect_changes]'
  assert_contains "$agents" 'get_architecture'
  assert_contains "$agents" 'detect_changes'
  assert_contains "$agents" 'multi_grep'
}


test_all_ai_agents_start_with_ponytail_and_caveman() {
  local agents soul
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  soul="$(<"$REPO_DIR/config/shared/ai/SOUL.md")"

  assert_contains "$agents" 'Ponytail and Caveman are active at `full`'
  assert_contains "$agents" 'main-agent and subagent startup'
  assert_contains "$soul" 'Ponytail and Caveman are active at `full`'
  assert_contains "$soul" 'main-agent and subagent startup'
  assert_contains "$HOME_CONFIG" '".hermes/SOUL.md" = forceSource ./shared/ai/SOUL.md;'
  assert_contains "$HOME_CONFIG" '".hermes/skills/productivity/ponytail/SKILL.md"'
}


test_shared_agent_skills_use_vendored_pinned_sources() {
  local pins windows
  pins="$REPO_DIR/config/shared/ai/skills/sources.json"
  windows="$(<"$REPO_DIR/dotfile.ps1")"

  assert_equals "0" "$(jq '[to_entries[] | select(.key != "schemaVersion") | select((.value.commit | test("^[0-9a-f]{40}$") | not) or (.value.observedArchiveSha256 | test("^[0-9a-f]{64}$") | not))] | length' "$pins")"
  for skill in caveman systematic-debugging test-driven-development verification-before-completion diff-review-qa ponytail ponytail-audit ponytail-debt ponytail-gain ponytail-help ponytail-review; do
    assert_file_exists "$REPO_DIR/config/shared/ai/skills/$skill/SKILL.md"
  done
  assert_contains "$HOME_CONFIG" '".agents/skills/caveman/SKILL.md" = forceSource ./shared/ai/skills/caveman/SKILL.md;'
  assert_not_contains "$HOME_CONFIG" '.agents/skills/caveman/README.md'
  assert_equals '["caveman/README.md"]' "$(jq -c '.caveman.excludedPaths' "$pins")"
  assert_equals "5" "$(jq '.superpowers.excludedPaths | length' "$pins")"
  for skill in systematic-debugging test-driven-development verification-before-completion diff-review-qa ponytail ponytail-audit ponytail-debt ponytail-gain ponytail-help ponytail-review; do
    assert_contains "$HOME_CONFIG" "\".agents/skills/$skill\" = forceSource ./shared/ai/skills/$skill;"
  done
  assert_not_contains "$HOME_CONFIG" 'ponytailSrc = pkgs.fetchFromGitHub'
  assert_not_contains "$HOME_CONFIG" 'cavemanSrc = pkgs.fetchFromGitHub'
  assert_not_contains "$HOME_CONFIG" 'superpowersSrc = pkgs.fetchFromGitHub'
  assert_not_contains "$windows" 'npx --yes skills add'
}


test_codex_seeds_have_no_remote_ponytail_marketplace() {
  local seed contents
  for seed in "$REPO_DIR/config/shared/ai/codex/config.toml" "$REPO_DIR/config/windows/ai/codex/config.toml"; do
    contents="$(<"$seed")"
    assert_not_contains "$contents" '[marketplaces.ponytail]'
    assert_not_contains "$contents" '[plugins."ponytail@ponytail"]'
    assert_not_contains "$contents" 'source_type = "git"'
    assert_not_contains "$contents" '[marketplaces.'
    assert_not_contains "$contents" '[projects.'
  done
}


test_all_ai_agents_delegate_efficiently() {
  local agents soul
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  soul="$(<"$REPO_DIR/config/shared/ai/SOUL.md")"

  for guidance in "$agents" "$soul"; do
    assert_contains "$guidance" 'multiple independent, substantial lanes'
    assert_contains "$guidance" 'parallel and asynchronously when supported'
    assert_contains "$guidance" 'one writer per worktree'
    assert_contains "$guidance" 'Do not delegate tiny, tightly serial, or duplicate work.'
    assert_contains "$guidance" 'Prefer 1–3 narrow children with only the context they need'
    assert_contains "$guidance" 'cheapest capable model'
    assert_contains "$guidance" 'Parent owns synthesis and final verification.'
  done

  assert_file_exists "$REPO_DIR/config/shared/ai/skills/diff-review-qa/SKILL.md"
  assert_contains "$HOME_CONFIG" '".agents/skills/diff-review-qa" = forceSource ./shared/ai/skills/diff-review-qa;'
}


test_install_arch_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }

  install_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -S --needed --noconfirm"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@arch-server"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _install_lix _load_nix_profile
}

test_update_arch_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo pacman"
  assert_equals "$(printf 'nix flake update --flake %s\nhome-manager switch --flake %s#testuser@arch-server' "$DOTFILES_DIR" "$DOTFILES_DIR")" "$output"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_update_arch_bootstraps_home_manager_when_missing() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix) return 0 ;;
        home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }

  update_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo pacman"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@arch-server"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile
}

test_update_arch_dry_run_shows_flake_update_then_home_manager_switch() {
  DRY=true

  local output
  output=$(update_arch 2>&1)

  assert_contains "$output" "nix flake update --flake $DOTFILES_DIR"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@arch-server"
}

test_debian_packages_are_bootstrap_only() {
  for pkg in curl git zsh procps file; do
    assert_contains "${DEBIAN_PACKAGES[*]}" "$pkg"
  done
  for pkg in build-essential xz-utils neovim starship nodejs tmux lazygit jujutsu ripgrep fd-find fzf fontconfig zoxide unzip; do
    if [[ " ${DEBIAN_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Debian apt packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_install_debian_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }

  install_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt install -y"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"
  assert_not_contains "$output" "neovim"

  unset -f command sudo _install_lix _load_nix_profile
}

test_update_debian_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo apt"
  assert_equals "$(printf 'nix flake update --flake %s\nhome-manager switch --flake %s#testuser@linux' "$DOTFILES_DIR" "$DOTFILES_DIR")" "$output"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_update_debian_bootstraps_home_manager_when_missing() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix) return 0 ;;
        home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }

  update_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo apt"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile
}

test_update_debian_dry_run_shows_flake_update_then_home_manager_switch() {
  DRY=true

  local output
  output=$(update_debian 2>&1)

  assert_contains "$output" "nix flake update --flake $DOTFILES_DIR"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
}

test_install_nixos_dry_run() {
  DRY=true

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "neovim"
}

test_update_nixos_dry_run() {
  DRY=true

  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "nix flake update --flake $DOTFILES_DIR"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--upgrade"
}

test_nixos_flake_target_reads_host_config_when_nix_is_missing() {
  mkdir -p "$DOTFILES_DIR/config"
  cat > "$DOTFILES_DIR/config/host.nix" <<'EOF'
{
  username = "testuser";
  hostName = "fallbackhost";
}
EOF
  nix() { return 127; }

  local output
  output=$(_nixos_flake_target 2>&1)

  assert_equals "$DOTFILES_DIR#fallbackhost" "$output"
  unset -f nix
}

test_nixos_flake_target_fails_when_hostname_missing() {
  nix() {
    if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "hostName" ]]; then
      return 1
    fi
  }

  local output exit_code=0
  output=$(_nixos_flake_target 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to resolve NixOS host name"
  assert_not_contains "$output" "$DOTFILES_DIR#"

  unset -f nix
}

test_home_manager_uses_current_nix_platform_api() {
  assert_contains "$HOME_CONFIG" 'pkgs.stdenv.hostPlatform.isLinux'
  assert_contains "$HOME_CONFIG" 'pkgs.stdenv.hostPlatform.isDarwin'
  assert_not_contains "$HOME_CONFIG" 'pkgs.stdenv.isLinux'
  assert_not_contains "$HOME_CONFIG" 'pkgs.stdenv.isDarwin'
  assert_contains "$(<"$REPO_DIR/packages/webcord-release.nix")" 'appimageTools.extract {'
}

test_home_manager_declares_default_apps() {
  local config="$HOME_CONFIG"

  assert_contains "$config" $'    thunar\n'
  assert_contains "$config" $'    xarchiver\n'
  assert_contains "$config" '"inode/directory" = [ "thunar.desktop" ];'
  assert_contains "$config" '"x-scheme-handler/https" = [ "google-chrome.desktop" ];'
  assert_contains "$config" '"application/zip" = [ "xarchiver.desktop" ];'
  assert_contains "$config" 'xdg.configFile."mimeapps.list".force = lib.mkIf pkgs.stdenv.hostPlatform.isLinux true;'
  assert_contains "$config" 'xdg.dataFile."applications/mimeapps.list".force = lib.mkIf pkgs.stdenv.hostPlatform.isLinux true;'
}

test_home_manager_installs_bitwarden_picker() {
  local home_config="$HOME_CONFIG" hypr_config="$HYPR_CONFIG"

  assert_contains "$home_config" "rbw"
  assert_contains "$home_config" '".local/bin/bitwarden-picker"'
  assert_contains "$home_config" './unix/bin/bitwarden-picker'
  assert_not_contains "$home_config" "rofi-rbw"
  assert_not_contains "$home_config" "wtype"
  assert_contains "$hypr_config" 'mainMod .. " + CTRL + Space"'
  assert_contains "$hypr_config" 'app .. "bitwarden-picker"'
}

test_home_manager_installs_anki() {
  assert_contains "$HOME_CONFIG" "anki.withAddons"
  assert_contains "$HOME_CONFIG" "ankiAddons.passfail2.withConfig"
  assert_contains "$HOME_CONFIG" 'pname = "zoom24";'
  assert_contains "$HOME_CONFIG" 'https://ankiweb.net/shared/download/1923741581'
  assert_contains "$HYPR_CONFIG" 'hl.dsp.exec_cmd(app .. anki)'
}

test_home_manager_installs_pinned_webcord_release() {
  local package="$REPO_DIR/packages/webcord-release.nix" flake
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$HOME_CONFIG" "webcord"
  assert_contains "$flake" 'webcord = final.callPackage ./packages/webcord-release.nix { };'
  assert_file_exists "$package"
  [[ -f "$package" ]] || return
  assert_contains "$(<"$package")" 'version = "'
  assert_contains "$(<"$package")" 'hash = "sha256-'
  assert_contains "$(<"$package")" "appimageTools.wrapType2"
}

test_home_manager_secures_google_drive_sync() {
  assert_contains "$HOME_CONFIG" $'    fuse3\n'
  assert_contains "$HOME_CONFIG" $'    rclone\n'
  assert_contains "$HOME_CONFIG" '--file-perms 0600 --dir-perms 0700'
  assert_contains "$HOME_CONFIG" 'UMask = "0077";'
  assert_contains "$HOME_CONFIG" 'ExecStopPost = "${pkgs.coreutils}/bin/chmod -R u=rwX,go= ${homeDir}/Documents/Drive ${homeDir}/Documents/.Drive-backup";'
}

test_network_services_apply_safe_process_sandbox() {
  local mount_service
  mount_service="$(awk '
    /systemd.user.services.google-drive-mount =/ { found = 1 }
    /systemd.user.services.google-drive-bisync =/ { exit }
    found { print }
  ' <<< "$HOME_CONFIG")"
  for setting in \
    'NoNewPrivileges = true;' \
    'RestrictSUIDSGID = true;' \
    'RestrictRealtime = true;' \
    'LockPersonality = true;' \
    'SystemCallArchitectures = "native";' \
    'RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];'; do
    assert_contains "$HOME_CONFIG" "$setting"
  done
  assert_equals "5" "$(grep -c 'Service = networkServiceHardening //' <<< "$HOME_CONFIG")"
  assert_equals "6" "$(grep -c 'UMask = "0077";' <<< "$HOME_CONFIG")"
  assert_equals "1" "$(grep -c 'NoNewPrivileges = false;' <<< "$HOME_CONFIG")"
  assert_contains "$mount_service" 'NoNewPrivileges = false;'
  for setting in \
    'RestrictSUIDSGID = true;' \
    'RestrictRealtime = true;' \
    'LockPersonality = true;' \
    'SystemCallArchitectures = "native";' \
    'RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];'; do
    assert_not_contains "$mount_service" "$setting"
  done
}

test_obsidian_service_skips_non_vault_directories() {
  assert_contains "$HOME_CONFIG" '[ -d "$vault/.obsidian" ] || continue'
}

test_google_drive_storage_sync() {
  local exit_code=0
  python3 "$REPO_DIR/scripts/google-drive-storage-sync.py" --self-test >/dev/null 2>&1 || exit_code=$?
  assert_equals "0" "$exit_code"
  assert_contains "$HOME_CONFIG" "systemd.user.services.google-drive-storage-sync"
  assert_contains "$HOME_CONFIG" "systemd.user.timers.google-drive-storage-sync"
  assert_contains "$HOME_CONFIG" 'OnCalendar = "daily";'
  assert_contains "$HOME_CONFIG" 'google-drive-sync.lock'
  assert_contains "$HOME_CONFIG" 'TimeoutStartSec = "infinity";'
}

test_storage_offsite_backup() {
  assert_contains "$HOME_CONFIG" "storageOffsiteBackup ? false"
  assert_contains "$HOME_CONFIG" 'lib.optionals storageOffsiteBackup [ pkgs.restic ]'
  assert_contains "$HOME_CONFIG" "systemd.user.services.storage-offsite-backup"
  assert_contains "$HOME_CONFIG" "systemd.user.timers.storage-offsite-backup"
  assert_contains "$HOME_CONFIG" 'RESTIC_REPOSITORY=rclone:gdrive:ServerBackup/restic'
  assert_contains "$HOME_CONFIG" '/mnt/storage/Storage/Documents /mnt/storage/Storage/Book /mnt/storage/Storage/Music'
  assert_contains "$HOME_CONFIG" 'ConditionPathIsMountPoint = "/mnt/storage";'
  assert_contains "$HOME_CONFIG" 'ConditionPathIsDirectory = ['
  assert_contains "$HOME_CONFIG" '"/mnt/storage/Storage/Documents"'
  assert_contains "$HOME_CONFIG" '"/mnt/storage/Storage/Book"'
  assert_contains "$HOME_CONFIG" '"/mnt/storage/Storage/Music"'
  assert_not_contains "$HOME_CONFIG" '/mnt/storage/Storage/Quan'
  assert_contains "$HOME_CONFIG" 'storage-offsite-backup-initialized'
  assert_contains "$HOME_CONFIG" 'storage-offsite-excludes'
  assert_contains "$HOME_CONFIG" "systemd.user.services.storage-offsite-maintenance"
  assert_contains "$HOME_CONFIG" 'home.activation.guardStorageOffsiteProfile'
  assert_contains "$HOME_CONFIG" 'lib.hm.dag.entryBefore [ "writeBoundary" ]'
  assert_contains "$HOME_CONFIG" 'Refusing generic Home Manager profile'
  assert_contains "$HOME_CONFIG" 'guardedHomeManager = pkgs.writeShellScriptBin "home-manager"'
  assert_contains "$HOME_CONFIG" 'lib.hiPrio guardedHomeManager'
  assert_contains "$HOME_CONFIG" 'config.programs.home-manager.package'
  assert_contains "$FLAKE_CONFIG" 'homeConfigurations."${machine.username}@arch-server"'
  assert_contains "$FLAKE_CONFIG" 'storageOffsiteBackup = true;'
}

test_home_manager_installs_screenshot_tools() {
  local home_config="$HOME_CONFIG" hypr_config="$HYPR_CONFIG"

  assert_contains "$home_config" "grim"
  assert_contains "$home_config" "slurp"
  assert_contains "$hypr_config" 'bind("Print"'
  assert_contains "$hypr_config" 'bind("SHIFT + Print"'
  assert_contains "$hypr_config" 'bind("CTRL + Print"'
}

test_home_manager_enables_fuzzel() {
  local home_config="$HOME_CONFIG" hypr_config="$HYPR_CONFIG"

  assert_contains "$home_config" "programs.fuzzel = lib.mkIf pkgs.stdenv.hostPlatform.isLinux"
  assert_contains "$home_config" 'terminal = "ghostty";'
  assert_contains "$home_config" 'launch-prefix = "uwsm app --";'
  assert_contains "$hypr_config" 'mainMod .. " + Space"'
  assert_contains "$hypr_config" 'hl.dsp.exec_cmd(app .. "fuzzel")'
}

test_hyprland_uses_uwsm_application_lifecycle() {
  local config="$HYPR_CONFIG"

  assert_contains "$config" 'local app         = "uwsm app -- "'
  assert_contains "$config" 'hl.dsp.exec_cmd(app .. "google-chrome-stable")'
  assert_not_contains "$config" "hl.dsp.exit()"
}

test_hyprshutdown_gracefully_ends_power_actions() {
  assert_contains "$HOME_CONFIG" "hyprshutdown"
  assert_contains "$NIXOS_CONFIG" 'BackgroundModeEnabled = false;'
  assert_contains "$HYPR_CONFIG" 'hl.dsp.exec_cmd("hyprshutdown")'
  assert_contains "$WAYBAR_CONFIG" '"logout": "uwsm app -- hyprshutdown"'
  assert_contains "$WAYBAR_CONFIG" '"reboot": "uwsm app -- hyprshutdown --post-cmd'
  assert_contains "$WAYBAR_CONFIG" 'systemctl reboot'
  assert_contains "$WAYBAR_CONFIG" '"poweroff": "uwsm app -- hyprshutdown --post-cmd'
  assert_contains "$WAYBAR_CONFIG" 'systemctl poweroff'
  assert_not_contains "$WAYBAR_CONFIG" 'scripts/logout-session.sh'
}

test_waybar_and_fcitx_use_session_lifecycle() {
  assert_contains "$HOME_CONFIG" "programs.waybar ="
  assert_contains "$HOME_CONFIG" "systemd.enable = pkgs.stdenv.hostPlatform.isLinux;"
  assert_not_contains "$HYPR_CONFIG" "scripts/reload-waybar.sh"
  assert_not_contains "$HYPR_CONFIG" 'fcitx5 -d'
  assert_contains "$HYPR_CONFIG" "systemctl --user restart waybar.service"
}

test_hyprland_adds_media_controls() {
  local home_config="$HOME_CONFIG" hypr_config="$HYPR_CONFIG"

  assert_contains "$home_config" "playerctl"
  assert_contains "$hypr_config" 'bind("XF86AudioPlay"'
  assert_contains "$hypr_config" 'bind("XF86AudioPrev"'
  assert_contains "$hypr_config" 'bind("XF86AudioNext"'
  assert_contains "$hypr_config" 'playerctl play-pause'
}

test_hyprland_removes_unused_input_and_tearing_config() {
  local config="$HYPR_CONFIG"

  assert_not_contains "$config" "allow_tearing"
  assert_not_contains "$config" "hl.gesture"
  assert_not_contains "$config" "no_hardware_cursors"
}

test_hyprland_adds_window_management_keybinds() {
  local config="$HYPR_CONFIG"

  assert_contains "$config" 'mainMod .. " + F"'
  assert_contains "$config" 'mainMod .. " + SHIFT + " .. key'
  assert_contains "$config" 'mainMod .. " + ALT + " .. key'
  assert_contains "$config" 'mainMod .. " + G"'
  assert_contains "$config" 'mainMod .. " + Tab"'
  assert_contains "$config" 'mainMod .. " + Z"'
  assert_contains "$config" 'hl.define_submap("resize"'
}

test_hyprland_exposes_keybind_list() {
  local config="$HYPR_CONFIG" script
  script="$(<"$REPO_DIR/scripts/show-keybinds.sh")"

  assert_contains "$config" 'description = description'
  assert_contains "$config" '$HOME/.local/bin/show-keybinds'
  assert_not_contains "$config" '$HOME/dotfiles/scripts/show-keybinds.sh'
  assert_contains "$HOME_CONFIG" '".local/bin/input-method-status"'
  assert_contains "$HOME_CONFIG" '".local/bin/hyprsunset-status"'
  assert_contains "$HOME_CONFIG" '".local/bin/show-keybinds"'
  assert_contains "$script" 'hyprctl binds -j'
  assert_contains "$script" 'fuzzel --dmenu'
}

test_waybar_shows_hyprsunset_status() {
  local config="$WAYBAR_CONFIG" style="$WAYBAR_STYLE" status_script="$SUNSET_STATUS_SCRIPT" day night

  assert_contains "$config" '"custom/hyprsunset"'
  assert_contains "$config" '$HOME/.local/bin/hyprsunset-status'
  assert_not_contains "$config" '$HOME/dotfiles/scripts/hyprsunset-status.sh'
  assert_contains "$style" "#custom-hyprsunset.active"
  assert_contains "$status_script" 'config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"'
  assert_not_contains "$status_script" 'repo="$(cd --'
  assert_not_contains "$status_script" "mapfile"

  day="$(HYPRSUNSET_RUNNING=true "$REPO_DIR/scripts/hyprsunset-status.sh" 12:00)"
  night="$(HYPRSUNSET_RUNNING=true "$REPO_DIR/scripts/hyprsunset-status.sh" 21:00)"
  assert_equals "inactive" "$(jq -r .class <<<"$day")"
  assert_equals "active" "$(jq -r .class <<<"$night")"
  assert_not_contains "$(jq -r .text <<<"$day")" ":"
  assert_not_contains "$(jq -r .text <<<"$night")" ":"
  assert_contains "$(jq -r .tooltip <<<"$day")" "20:00"
  assert_contains "$(jq -r .tooltip <<<"$night")" "07:00"
}

test_waybar_shows_input_method() {
  local config="$WAYBAR_CONFIG" style="$WAYBAR_STYLE" status_script="$INPUT_METHOD_STATUS_SCRIPT" english vietnamese chinese

  assert_contains "$config" '"custom/input-method"'
  assert_contains "$config" '$HOME/.local/bin/input-method-status'
  assert_contains "$config" '"on-click": "$HOME/.local/bin/input-method-status --next"'
  assert_not_contains "$config" '$HOME/dotfiles/scripts/input-method-status.sh'
  assert_contains "$config" '"interval": 5'
  assert_contains "$style" "#custom-input-method"

  english="$("$REPO_DIR/scripts/input-method-status.sh" keyboard-us)"
  vietnamese="$("$REPO_DIR/scripts/input-method-status.sh" unikey)"
  chinese="$("$REPO_DIR/scripts/input-method-status.sh" pinyin)"
  assert_contains "$(jq -r .text <<<"$english")" "EN"
  assert_contains "$(jq -r .tooltip <<<"$english")" "English"
  assert_contains "$(jq -r .text <<<"$vietnamese")" "VI"
  assert_contains "$(jq -r .tooltip <<<"$vietnamese")" "Vietnamese"
  assert_contains "$(jq -r .text <<<"$chinese")" "中"
  assert_contains "$(jq -r .tooltip <<<"$chinese")" "Chinese"

  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/fcitx5-remote" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-n" ]]; then
  printf '%s\n' "$FCITX_CURRENT"
elif [[ "$1" == "-s" ]]; then
  printf '%s\n' "$2" > "$FCITX_SWITCH_LOG"
fi
EOF
  chmod +x "$TEST_TMPDIR/bin/fcitx5-remote"
  PATH="$TEST_TMPDIR/bin:$PATH" FCITX_CURRENT=unikey FCITX_SWITCH_LOG="$TEST_TMPDIR/switch" \
    "$REPO_DIR/scripts/input-method-status.sh" --next
  assert_equals "pinyin" "$(<"$TEST_TMPDIR/switch")"
}

test_waybar_power_menu_logs_out_gracefully() {
  assert_contains "$POWER_MENU" 'id="logout"'
  assert_contains "$POWER_MENU" '<property name="label">Log Out</property>'
  assert_contains "$WAYBAR_CONFIG" '"logout": "uwsm app -- hyprshutdown"'
}

test_waybar_audio_tooltip_shows_selected_output() {
  assert_contains "$WAYBAR_CONFIG" '"tooltip-format": "Volume: {volume}%\nOutput: {desc}"'
}

test_waybar_audio_click_opens_mixer() {
  assert_contains "$HOME_CONFIG" "pavucontrol"
  assert_contains "$WAYBAR_CONFIG" '"on-click": "pavucontrol"'
}

test_waybar_shows_media_status() {
  local config="$WAYBAR_CONFIG" style="$WAYBAR_STYLE"

  assert_contains "$config" '"mpris"'
  assert_contains "$config" '"format": "{status_icon} {dynamic}"'
  assert_contains "$config" '"format-paused": "{status_icon}"'
  assert_contains "$config" '"playing": "󰐊"'
  assert_contains "$style" "#mpris.stopped"
  assert_contains "$style" "padding: 0;"
  assert_contains "$config" '"class<thunar>": ""'
  assert_not_contains "$config" "org.kde.dolphin"
  assert_contains "$style" "#mpris"
}

test_hyprland_configures_actual_mouse() {
  local config="$HYPR_CONFIG"

  assert_contains "$config" 'name = "logitech-g502-1"'
  assert_not_contains "$config" 'name = "logitech-g502"'
}

test_home_manager_enables_hyprsunset() {
  local home_config="$HOME_CONFIG" sunset_config="$SUNSET_CONFIG"

  assert_contains "$home_config" "services.hyprsunset.enable = pkgs.stdenv.hostPlatform.isLinux;"
  assert_contains "$home_config" "systemd.user.services.hyprsunset.Unit.X-Restart-Triggers"
  assert_contains "$sunset_config" "time = 07:00"
  assert_contains "$sunset_config" "time = 20:00"
  assert_contains "$sunset_config" "temperature = 4500"
}

test_home_manager_enables_clipboard_persistence() {
  local config="$HOME_CONFIG"

  assert_contains "$config" "services.wl-clip-persist = lib.mkIf pkgs.stdenv.hostPlatform.isLinux"
  assert_contains "$config" 'clipboardType = "regular";'
  assert_contains "$config" 'systemd.user.services.wl-clip-persist.Unit.ConditionEnvironment = "WAYLAND_DISPLAY";'
}

test_home_manager_enables_mako() {
  local config="$HOME_CONFIG"

  assert_contains "$config" "services.mako = lib.mkIf pkgs.stdenv.hostPlatform.isLinux"
  assert_contains "$config" 'output = "DP-3";'
  assert_contains "$config" 'default-timeout = 5000;'
}

test_home_manager_declares_default_user_dirs() {
  local config="$HOME_CONFIG"

  assert_contains "$config" 'documents = "${homeDir}/Documents";'
  assert_contains "$config" 'download = "${homeDir}/Downloads";'
  assert_contains "$config" "desktop = null;"
}

test_home_manager_enables_hyprpolkitagent() {
  local config="$HOME_CONFIG"

  assert_contains "$config" "services.hyprpolkitagent.enable = pkgs.stdenv.hostPlatform.isLinux;"
  assert_contains "$config" 'systemd.user.services.hyprpolkitagent.Unit.ConditionEnvironment = "WAYLAND_DISPLAY";'
}

test_home_manager_forces_jj_config_takeover() {
  local config="$HOME_CONFIG"

  assert_contains "$config" '"${homeDir}/.config/jj/config.toml".force = true;'
}

test_nixos_enables_gnome_keyring() {
  local config="$NIXOS_CONFIG"

  assert_contains "$config" "services.gnome.gnome-keyring.enable = true;"
}

test_nixos_configures_nvidia_driver() {
  local config="$NIXOS_CONFIG"

  assert_contains "$config" 'services.xserver.videoDrivers = [ "nvidia" ];'
  assert_contains "$config" "modesetting.enable = true;"
  assert_contains "$config" "powerManagement.enable = true;"
  assert_contains "$config" "open = true;"
  assert_contains "$config" "nvidiaPackages.stable"
}

test_nixos_uses_uwsm_session() {
  local nix_config hypr_config
  nix_config="$NIXOS_CONFIG"
  hypr_config="$HYPR_CONFIG"

  assert_contains "$nix_config" "withUWSM = true;"
  assert_contains "$nix_config" 'uwsm start -e -D Hyprland hyprland.desktop'
  assert_not_contains "$hypr_config" "dbus-update-activation-environment"
  assert_not_contains "$hypr_config" "hl.env("
}

test_install_nixos_uses_flake_switch() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  install_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--impure"

  unset -f sudo
}

test_update_nixos_updates_flake_then_switches() {
  local calls="$TEST_TMPDIR/update.log"
  host_config_value() { printf 'testhost\n'; }
  nix() { printf 'nix %s\n' "$*" >> "$calls"; }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }

  update_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_equals "$(printf 'nix flake update --flake %s\nsudo nixos-rebuild switch --flake %s#testhost' "$DOTFILES_DIR" "$DOTFILES_DIR")" "$output"
  assert_not_contains "$output" "--upgrade"
  assert_not_contains "$output" "--impure"

  unset -f host_config_value nix sudo
}

test_update_nixos_reloads_running_hyprland() {
  local calls="$TEST_TMPDIR/hyprctl.log"
  nix() { :; }
  sudo() { :; }
  hyprctl() { printf '%s\n' "$*" >> "$calls"; }
  local HYPRLAND_INSTANCE_SIGNATURE=test

  update_nixos >/dev/null 2>&1

  assert_equals "reload" "$(<"$calls")"
  unset -f nix sudo hyprctl
}

test_install_packages_dispatches_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=true

  local output
  output=$(OS_RELEASE="$osrel" install_packages 2>&1)

  assert_contains "$output" "NixOS"
}

test_set_zsh_default_skips_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=false

  local output
  output=$(OS_RELEASE="$osrel" set_zsh_default 2>&1)

  assert_contains "$output" "declaratively"
}
