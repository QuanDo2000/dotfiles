#!/usr/bin/env bash
# Tests for tracked NixOS configuration invariants.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_greetd_launches_hyprland_through_nixos_wrapper() {
  local config_text
  config_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$config_text" "--cmd start-hyprland"
  assert_not_contains "$config_text" "--cmd Hyprland"
}

test_flake_uses_flat_nix_config_files() {
  local flake_text
  flake_text="$(<"$REPO_DIR/flake.nix")"

  assert_file_exists "$REPO_DIR/config/home.nix"
  assert_file_exists "$REPO_DIR/config/host.nix"
  assert_file_exists "$REPO_DIR/config/hardware-configuration.nix"
  assert_file_exists "$REPO_DIR/config/nixos.nix"
  assert_file_exists "$REPO_DIR/config/darwin.nix"
  assert_contains "$flake_text" "./config/home.nix"
  assert_contains "$flake_text" "./config/nixos.nix"
  assert_contains "$flake_text" "./config/darwin.nix"
  assert_not_contains "$flake_text" "config/nix/"
}

test_nixos_uses_tracked_host_config() {
  local host_text nixos_text configuration_text
  host_text="$(<"$REPO_DIR/config/host.nix")"
  nixos_text="$(<"$REPO_DIR/config/nixos.nix")"
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$host_text" 'username = "quando"'
  assert_contains "$host_text" 'hostName = "nixos"'
  assert_contains "$host_text" 'timeZone = "America/Los_Angeles"'
  assert_contains "$host_text" 'stateVersion = "26.05"'
  assert_contains "$nixos_text" "import ./host.nix"
  assert_contains "$configuration_text" "import ../host.nix"
  assert_not_contains "$nixos_text" "/etc/nixos/machine.nix"
  assert_not_contains "$configuration_text" "/etc/nixos/machine.nix"
}

test_nixos_uses_tracked_hardware_config() {
  local hardware_text configuration_text
  hardware_text="$(<"$REPO_DIR/config/hardware-configuration.nix")"
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$hardware_text" 'nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"'
  assert_contains "$hardware_text" 'fileSystems."/"'
  assert_contains "$configuration_text" "../hardware-configuration.nix"
  assert_not_contains "$configuration_text" "/etc/nixos/hardware-configuration.nix"
}

test_home_config_uses_program_home_manager_cli() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "home.packages"
  assert_contains "$home_text" "programs.home-manager.enable = true"
  assert_not_contains "$home_text" "    home-manager"
  assert_contains "$home_text" "neovim"
}

test_home_config_manages_git_and_starship() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "home.file.\".gitconfig\""
  assert_contains "$home_text" "source = ./shared/.gitconfig"
  assert_contains "$home_text" "force = true"
  assert_contains "$home_text" "xdg.configFile.\"starship.toml\""
  assert_contains "$home_text" "./shared/config/starship.toml"
}

test_home_config_owns_remaining_dotfiles() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "home.file.\".vimrc\""
  assert_contains "$home_text" "source = ./shared/.vimrc"
  assert_contains "$home_text" "home.file.\".tmux.conf\""
  assert_contains "$home_text" "source = ./unix/.tmux.conf"
  assert_contains "$home_text" "home.file.\".zprofile\""
  assert_contains "$home_text" "source = ./unix/.zprofile"
  assert_contains "$home_text" "home.file.\".zshrc.base\""
  assert_contains "$home_text" "source = ./unix/.zshrc.base"
  assert_contains "$home_text" "home.file.\".ssh/config\""
  assert_contains "$home_text" "source = ./shared/.ssh/config"
  assert_contains "$home_text" "home.file.\".claude/settings.json\""
  assert_contains "$home_text" "source = ./shared/ai/claude/settings.json"
  assert_contains "$home_text" "home.file.\".codex/config.toml\""
  assert_contains "$home_text" "source = ./shared/ai/codex/config.toml"
  assert_contains "$home_text" "home.file.\".zshrc.mac\""
  assert_contains "$home_text" "source = ./mac/.zshrc.mac"
  assert_contains "$home_text" "home.file.\".local/bin/caf\""
  assert_contains "$home_text" "source = ./mac/bin/caf"
  assert_contains "$home_text" "pkgs.stdenv.isDarwin"
}

test_home_manager_backs_up_existing_files() {
  local nixos_text darwin_text
  nixos_text="$(<"$REPO_DIR/config/nixos.nix")"
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$nixos_text" "home-manager.backupFileExtension = \"before-home-manager\""
  assert_contains "$darwin_text" "home-manager.backupFileExtension = \"before-home-manager\""
}

test_darwin_config_manages_core_packages() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$darwin_text" "nix.settings.experimental-features"
  assert_contains "$darwin_text" "nixpkgs.config.allowUnfree = true"
  assert_contains "$darwin_text" "environment.systemPackages"
  assert_contains "$darwin_text" "neovim"
  assert_contains "$darwin_text" "lazygit"
  assert_contains "$darwin_text" "jujutsu"
  assert_contains "$darwin_text" "ast-grep"
  assert_contains "$darwin_text" "programs.zsh.enable = true"
  assert_contains "$darwin_text" "system.primaryUser = \"quando\""
}

test_home_config_links_zsh_plugins_from_nix() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "xdg.dataFile.\"zsh/plugins/zsh-autosuggestions\""
  assert_contains "$home_text" "pkgs.zsh-autosuggestions"
  assert_contains "$home_text" "xdg.dataFile.\"zsh/plugins/fast-syntax-highlighting\""
  assert_contains "$home_text" "pkgs.zsh-fast-syntax-highlighting"
  assert_contains "$home_text" "xdg.dataFile.\"zsh/plugins/fzf-tab\""
  assert_contains "$home_text" "pkgs.zsh-fzf-tab"
  assert_contains "$home_text" "force = true"
}

test_home_config_links_tmux_plugins_from_nix() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "home.file.\".tmux/plugins/tmux-yank\""
  assert_contains "$home_text" "pkgs.tmuxPlugins.yank"
  assert_contains "$home_text" "home.file.\".tmux/plugins/catppuccin/tmux\""
  assert_contains "$home_text" "pkgs.tmuxPlugins.catppuccin"
  assert_contains "$home_text" "force = true"
}

test_home_config_owns_existing_xdg_configs() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "xdg.configFile.\"jj\""
  assert_contains "$home_text" "./shared/config/jj"
  assert_contains "$home_text" "xdg.configFile.\"nvim\""
  assert_contains "$home_text" "./shared/config/nvim"
  assert_contains "$home_text" "xdg.configFile.\"fcitx5\""
  assert_contains "$home_text" "./unix/config/fcitx5"
  assert_contains "$home_text" "xdg.configFile.\"ghostty/config\""
  assert_contains "$home_text" "./unix/config/ghostty/config"
  assert_contains "$home_text" "xdg.configFile.\"hypr\""
  assert_contains "$home_text" "./unix/config/hypr"
  assert_contains "$home_text" "xdg.configFile.\"waybar\""
  assert_contains "$home_text" "./unix/config/waybar"
  assert_contains "$home_text" "force = true"
}
