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
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@arch-server"
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

test_update_arch_dry_run_shows_home_manager_switch() {
  DRY=true

  local output
  output=$(update_arch 2>&1)

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
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
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

test_update_debian_dry_run_shows_home_manager_switch() {
  DRY=true

  local output
  output=$(update_debian 2>&1)

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

test_home_manager_declares_default_apps() {
  local config="$HOME_CONFIG"

  assert_contains "$config" $'    thunar\n'
  assert_contains "$config" $'    xarchiver\n'
  assert_contains "$config" '"inode/directory" = [ "thunar.desktop" ];'
  assert_contains "$config" '"x-scheme-handler/https" = [ "google-chrome.desktop" ];'
  assert_contains "$config" '"application/zip" = [ "xarchiver.desktop" ];'
  assert_contains "$config" 'xdg.configFile."mimeapps.list".force = lib.mkIf pkgs.stdenv.isLinux true;'
  assert_contains "$config" 'xdg.dataFile."applications/mimeapps.list".force = lib.mkIf pkgs.stdenv.isLinux true;'
}

test_home_manager_installs_bitwarden_picker() {
  local home_config="$HOME_CONFIG" hypr_config="$HYPR_CONFIG"

  assert_contains "$home_config" "rbw"
  assert_contains "$home_config" "rofi-rbw"
  assert_contains "$home_config" "wtype"
  assert_contains "$home_config" 'selector=fuzzel'
  assert_contains "$home_config" 'typer=wtype'
  assert_contains "$home_config" 'prompt='
  assert_contains "$home_config" 'selector-args=--prompt "" --placeholder "Search vault…" --inner-pad 8'
  assert_contains "$home_config" 'action=copy'
  assert_contains "$home_config" 'target=menu'
  assert_not_contains "$home_config" 'target=password'
  assert_contains "$home_config" 'clear-after=30'
  assert_contains "$home_config" 'no-cache=true'
  assert_contains "$hypr_config" 'mainMod .. " + CTRL + Space"'
  assert_contains "$hypr_config" 'app .. "rofi-rbw"'
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
  assert_contains "$(<"$package")" 'version = "4.14.0";'
  assert_contains "$(<"$package")" "appimageTools.wrapType2"
}

test_home_manager_secures_google_drive_sync() {
  assert_contains "$HOME_CONFIG" $'    fuse3\n'
  assert_contains "$HOME_CONFIG" $'    rclone\n'
  assert_contains "$HOME_CONFIG" '--file-perms 0600 --dir-perms 0700'
  assert_contains "$HOME_CONFIG" 'UMask = "0077";'
  assert_contains "$HOME_CONFIG" 'ExecStopPost = "${pkgs.coreutils}/bin/chmod -R u=rwX,go= ${homeDir}/Documents/Drive ${homeDir}/Documents/.Drive-backup";'
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

  assert_contains "$home_config" "programs.fuzzel = lib.mkIf pkgs.stdenv.isLinux"
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
  assert_contains "$HOME_CONFIG" "systemd.enable = pkgs.stdenv.isLinux;"
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
  assert_contains "$config" 'scripts/show-keybinds.sh'
  assert_contains "$script" 'hyprctl binds -j'
  assert_contains "$script" 'fuzzel --dmenu'
}

test_waybar_shows_hyprsunset_status() {
  local config="$WAYBAR_CONFIG" style="$WAYBAR_STYLE" status_script="$SUNSET_STATUS_SCRIPT" day night

  assert_contains "$config" '"custom/hyprsunset"'
  assert_contains "$config" 'scripts/hyprsunset-status.sh'
  assert_contains "$style" "#custom-hyprsunset.active"
  assert_contains "$status_script" 'repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"'
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
  assert_contains "$config" 'scripts/input-method-status.sh'
  assert_contains "$config" '"on-click": "$HOME/dotfiles/scripts/input-method-status.sh --next"'
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

  assert_contains "$home_config" "services.hyprsunset.enable = pkgs.stdenv.isLinux;"
  assert_contains "$home_config" "systemd.user.services.hyprsunset.Unit.X-Restart-Triggers"
  assert_contains "$sunset_config" "time = 07:00"
  assert_contains "$sunset_config" "time = 20:00"
  assert_contains "$sunset_config" "temperature = 4500"
}

test_home_manager_enables_clipboard_persistence() {
  local config="$HOME_CONFIG"

  assert_contains "$config" "services.wl-clip-persist = lib.mkIf pkgs.stdenv.isLinux"
  assert_contains "$config" 'clipboardType = "regular";'
}

test_home_manager_enables_mako() {
  local config="$HOME_CONFIG"

  assert_contains "$config" "services.mako = lib.mkIf pkgs.stdenv.isLinux"
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

  assert_contains "$config" "services.hyprpolkitagent.enable = pkgs.stdenv.isLinux;"
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
  assert_contains "$output" "nix flake update --flake $DOTFILES_DIR"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
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
