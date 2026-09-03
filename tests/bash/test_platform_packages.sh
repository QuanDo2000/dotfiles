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
  for pkg in neovim starship nodejs tmux lazygit jujutsu ripgrep fd fzf fontconfig jq openssh ttf-firacode-nerd; do
    if [[ " ${ARCH_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Arch pacman packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}


test_pi_web_access_is_pinned() {
  local config="$REPO_DIR/config/shared/ai/pi/web-search.json"

  assert_equals "true" "$(jq -r '.dependencies["pi-web-access"] | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$REPO_DIR/config/shared/ai/pi/extensions/package.json")"
  assert_file_exists "$config"
  if [[ -f "$config" ]]; then
    assert_equals "none" "$(jq -r '.workflow' "$config")"
  fi
}

test_pi_model_cycling_shortcuts_are_disabled() {
  local keybindings="$REPO_DIR/config/shared/ai/pi/keybindings.json"

  assert_file_exists "$keybindings"
  if [[ -f "$keybindings" ]]; then
    assert_exit_code 0 jq -e '
      .["app.model.cycleForward"] == [] and
      .["app.model.cycleBackward"] == []
    ' "$keybindings"
  fi
}

test_all_ai_agents_start_with_shared_policy() {
  local agents soul guidance
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  soul="$(<"$REPO_DIR/config/shared/ai/SOUL.md")"

  for guidance in "$agents" "$soul"; do
    assert_contains "$guidance" 'Apply these fixed rules at every main-agent and subagent startup.'
    assert_contains "$guidance" '**Minimal implementation:**'
    assert_contains "$guidance" 'stop at the first solution that works'
    assert_contains "$guidance" 'standard-library, native-platform, and installed-dependency solutions'
    assert_contains "$guidance" 'Prefer deletion and boring code.'
    assert_contains "$guidance" 'Mark deliberate limitations with a `debt:` comment naming the ceiling and upgrade trigger.'
    assert_contains "$guidance" '**Terse communication:**'
  done
}


test_pi_uses_upstream_quit_command() {
  local package
  package="$(<"$REPO_DIR/packages/pi-agent.nix")"

  assert_not_contains "$package" "dist/core/slash-commands.js"
  assert_not_contains "$package" "dist/modes/interactive/interactive-mode.js"
}


test_shared_agent_skills_use_vendored_pinned_sources() {
  local pins windows
  pins="$REPO_DIR/config/shared/ai/skills/sources.json"
  windows="$(<"$REPO_DIR/dotfile.ps1")"

  assert_equals "0" "$(jq '[to_entries[] | select(.key != "schemaVersion") | select((.value.commit | test("^[0-9a-f]{40}$") | not) or (.value.observedArchiveSha256 | test("^[0-9a-f]{64}$") | not))] | length' "$pins")"
  for skill in systematic-debugging test-driven-development; do
    assert_file_exists "$REPO_DIR/config/shared/ai/skills/$skill/SKILL.md"
  done
  assert_not_contains "$windows" 'npx --yes skills add'
}


test_skill_retrospective_is_installed_cross_platform() {
  local skill windows
  skill="$REPO_DIR/config/shared/ai/skills/skill-retrospective/SKILL.md"
  windows="$(<"$REPO_DIR/dotfile.ps1")"

  assert_file_exists "$skill"
  assert_contains "$windows" "'systematic-debugging', 'test-driven-development', 'skill-retrospective'"
  assert_contains "$(<"$skill")" 'Use bounded session search rather than scanning all history by default.'
  assert_contains "$(<"$skill")" 'Do not assign numeric grades or composite scores.'
  assert_contains "$(<"$skill")" 'Do not modify installed skills without explicit user approval.'
}


test_agents_own_complexity_audit_and_debt_policy() {
  local agents soul guidance
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  soul="$(<"$REPO_DIR/config/shared/ai/SOUL.md")"

  for guidance in "$agents" "$soul"; do
    assert_contains "$guidance" 'For explicit whole-repository complexity or dependency audits'
    assert_contains "$guidance" 'For explicit diff complexity reviews, inspect changed and impacted code'
    assert_contains "$guidance" '`delete`, `stdlib`, `native`, `yagni`, or `shrink`'
    assert_contains "$guidance" 'For debt-ledger requests, search `debt:` comments'
    assert_contains "$guidance" 'tag markers without one as `no-trigger`'
  done
}


test_all_ai_agents_delegate_efficiently() {
  local agents debugging_skill soul
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  debugging_skill="$(<"$REPO_DIR/config/shared/ai/skills/systematic-debugging/SKILL.md")"
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

  assert_contains "$agents" 'Before launching, check active and completed runs for the same lane and unchanged target revision.'
  assert_contains "$agents" 'Treat reviewers as static: never ask them to run shell commands, tests, lint, typecheck, builds, or mutations.'
  assert_contains "$agents" 'When a matched reusable skill governs delegated work, pass only that skill explicitly to the child.'
  assert_contains "$agents" 'Normally use one fan-out wave; launch another only for a changed target or unresolved evidence gap.'
  assert_contains "$debugging_skill" 'Use the `test-driven-development` skill for writing proper failing tests'
  assert_contains "$debugging_skill" 'Follow the global verification policy before claiming success.'
  assert_contains "$agents" 'For explicit code reviews, report findings only: severity `P0`–`P3`, confidence, exact `path:line`, concrete failure mode, smallest fix, and residual risk.'
  assert_contains "$agents" 'Reject praise, style-only noise, speculative findings, duplicates, and claims unsupported by source or supplied validation evidence.'

  for guidance in "$agents" "$soul"; do
    assert_contains "$guidance" 'Before claiming completion, committing, or moving on, map each claim to the smallest authoritative command or live-state check'
    assert_contains "$guidance" 'Use focused checks while iterating and broad required suites once after the final change.'
  done
}


test_agents_recommend_promoting_reusable_hermes_skills() {
  local agents
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"

  assert_contains "$agents" 'Recommend promotion when a Hermes-generated skill is useful across machines or projects.'
  assert_contains "$agents" 'Do not copy it automatically.'
  assert_contains "$agents" 'config/shared/ai/skills/<name>/'
  assert_contains "$agents" 'config/home.nix'
  assert_contains "$agents" 'Windows `InstallAiSkills`'
  assert_contains "$agents" 'Sanitize machine-specific paths, secrets, and assumptions before copying'
  assert_contains "$agents" 'Verify discovery in every intended harness'
  assert_contains "$agents" 'remove the Hermes copy only after tracked installation is verified'
}


test_arch_bootstrap_skips_pacman_when_packages_are_installed() {
  DRY=false
  local calls="$TEST_TMPDIR/arch-bootstrap.log"
  pacman() {
    [[ "${1:-}" == "-Q" ]] && return 0
    printf 'pacman %s\n' "$*" >> "$calls"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }

  _install_native_bootstrap_packages arch

  assert_equals "" "$(cat "$calls" 2>/dev/null || true)"
  unset -f pacman sudo
}

test_debian_bootstrap_skips_apt_when_packages_are_installed() {
  DRY=false
  local calls="$TEST_TMPDIR/debian-bootstrap.log"
  dpkg-query() { printf 'install ok installed'; }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }

  _install_native_bootstrap_packages debian

  assert_equals "" "$(cat "$calls" 2>/dev/null || true)"
  unset -f dpkg-query sudo
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
  pacman() { return 1; }
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

  unset -f command pacman sudo _install_lix _load_nix_profile
}







test_set_zsh_default_tolerates_unset_shell() {
  DRY=false
  detect_platform() { printf 'debian\n'; }
  command() {
    if [[ "${1:-}" == -v && "${2:-}" == zsh ]]; then printf '/bin/zsh\n'; return 0; fi
    builtin command "$@"
  }
  chsh() { :; }
  local old_shell="${SHELL-}" had_shell=false
  [[ -v SHELL ]] && had_shell=true
  unset SHELL

  assert_exit_code 0 set_zsh_default

  [[ "$had_shell" == true ]] && export SHELL="$old_shell" || unset SHELL
  unset -f detect_platform command chsh
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
  dpkg-query() { return 1; }
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

  unset -f command dpkg-query sudo _install_lix _load_nix_profile
}







test_install_nixos_dry_run() {
  DRY=true

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "neovim"
}

test_install_nixos_wsl_dry_run_uses_separate_target() {
  DRY=true
  is_wsl() { return 0; }

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost-wsl"
  unset -f is_wsl
}

test_install_nixos_wsl_stages_username_change_without_user_sync() {
  local calls="$TEST_TMPDIR/wsl-bootstrap.log"
  DRY=false
  is_wsl() { return 0; }
  detect_platform() { printf 'nixos\n'; }
  id() { printf 'nixos\n'; }
  host_config_value() {
    case "$1" in
      hostName) printf 'testhost\n' ;;
      username) printf 'quando\n' ;;
    esac
  }
  sudo() { printf '%s\n' "$*" >> "$calls"; }
  _sync_neovim() { printf 'neovim-sync\n' >> "$calls"; }
  set_zsh_default() { printf 'set-zsh\n' >> "$calls"; }

  install_packages >/dev/null

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild boot --flake $DOTFILES_DIR#testhost-wsl"
  assert_not_contains "$output" "nixos-rebuild switch"
  assert_not_contains "$output" "neovim-sync"
  assert_not_contains "$output" "set-zsh"
  unset -f is_wsl detect_platform id host_config_value sudo _sync_neovim set_zsh_default
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

test_home_manager_installs_bitwarden_picker() {
  local hypr_config="$HYPR_CONFIG"

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

test_arch_bootstrap_declares_host_fuse3() {
  assert_contains "$(<"$REPO_DIR/scripts/packages.sh")" 'base-devel curl git zsh fuse3'
}

test_home_manager_installs_pinned_webcord_release() {
  local package="$REPO_DIR/packages/webcord-release.nix" flake
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$flake" 'webcord = final.callPackage ./packages/webcord-release.nix { };'
  assert_file_exists "$package"
  [[ -f "$package" ]] || return
  assert_contains "$(<"$package")" 'version = "'
  assert_contains "$(<"$package")" 'hash = "sha256-'
  assert_contains "$(<"$package")" "appimageTools.wrapType2"
}

test_obsidian_uses_native_editor_features() {
  local plugins="$REPO_DIR/config/shared/obsidian/community-plugins.json"

  assert_exit_code 0 jq -e '
    all(.[]; . != "code-block-copy" and . != "url-into-selection" and . != "table-editor-obsidian" and . != "pane-relief")
  ' "$plugins"
  assert_not_contains "$(<"$REPO_DIR/config/shared/obsidian/plugins/obsidian-style-settings/data.json")" "pane-relief@@"
  assert_not_contains "$HOME_CONFIG" 'plugins/table-editor-obsidian/data.json'
  assert_equals false "$([[ -e "$REPO_DIR/config/shared/obsidian/plugins/table-editor-obsidian/data.json" ]] && echo true || echo false)"
}

test_obsidian_service_skips_non_vault_directories() {
  assert_contains "$HOME_CONFIG" '[ -d "$vault/.obsidian" ] || continue'
}

test_google_drive_storage_sync() {
  local exit_code=0
  python3 "$REPO_DIR/scripts/google-drive-storage-sync.py" --self-test >/dev/null 2>&1 || exit_code=$?
  assert_equals "0" "$exit_code"
}

test_storage_offsite_backup() {
  local exit_code=0
  bash "$REPO_DIR/config/arch-server/restic-recover" --self-test >/dev/null 2>&1 || exit_code=$?
  assert_equals "0" "$exit_code"
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
  local hypr_config="$HYPR_CONFIG"

  assert_contains "$hypr_config" 'bind("Print"'
  assert_contains "$hypr_config" 'bind("SHIFT + Print"'
  assert_contains "$hypr_config" 'bind("CTRL + Print"'
}

test_home_manager_enables_fuzzel() {
  local hypr_config="$HYPR_CONFIG"

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
  assert_not_contains "$HYPR_CONFIG" "scripts/reload-waybar.sh"
  assert_not_contains "$HYPR_CONFIG" 'fcitx5 -d'
  assert_contains "$HYPR_CONFIG" "systemctl --user restart waybar.service"
}

test_hyprland_adds_media_controls() {
  local hypr_config="$HYPR_CONFIG"

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
  local sunset_config="$SUNSET_CONFIG"

  assert_contains "$sunset_config" "time = 07:00"
  assert_contains "$sunset_config" "time = 20:00"
  assert_contains "$sunset_config" "temperature = 4500"
}

test_nixos_enables_gnome_keyring() {
  local config="$NIXOS_CONFIG"

  assert_contains "$config" "services.gnome.gnome-keyring.enable = true;"
}

test_nixos_wsl_has_separate_hardware_free_configuration() {
  local path="$REPO_DIR/config/nixos-wsl/configuration.nix"
  assert_file_exists "$path"
  [[ -f "$path" ]] || return

  local config
  config="$(<"$path")"
  assert_contains "$FLAKE_CONFIG" 'nixos-wsl.nixosModules.default'
  assert_contains "$FLAKE_CONFIG" 'nixosConfigurations."${machine.hostName}-wsl"'
  assert_contains "$config" 'wsl.enable = true;'
  assert_contains "$config" 'wsl.defaultUser = machine.username;'
  assert_contains "$config" 'wsl.wslConf.interop.appendWindowsPath = false;'
  assert_not_contains "$config" 'hardware-configuration.nix'
  assert_not_contains "$config" 'systemd-boot'
  assert_not_contains "$config" 'hardware.nvidia'
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





test_nixos_rebuild_reloads_running_hyprland() {
  local calls="$TEST_TMPDIR/hyprctl.log"
  host_config_value() { printf 'testhost\n'; }
  sudo() { :; }
  hyprctl() { printf '%s\n' "$*" >> "$calls"; }
  command() {
    if [[ "${1:-}" == -v && "${2:-}" == hyprctl ]]; then return 0; fi
    builtin command "$@"
  }
  export HYPRLAND_INSTANCE_SIGNATURE=test

  _nixos_rebuild_switch

  assert_equals 'reload' "$(<"$calls")"
  unset HYPRLAND_INSTANCE_SIGNATURE
  unset -f host_config_value sudo hyprctl command
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
