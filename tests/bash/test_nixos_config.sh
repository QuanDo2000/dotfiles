#!/usr/bin/env bash
# Tests for tracked NixOS configuration invariants.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_greetd_launches_hyprland_through_nixos_wrapper() {
  local config_text
  config_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$config_text" "--cmd start-hyprland"
  assert_not_contains "$config_text" "--cmd Hyprland"
}

test_hyprland_launches_obsidian_with_super_n() {
  local hypr_text
  hypr_text="$(<"$REPO_DIR/config/unix/config/hypr/hyprland.lua")"

  assert_contains "$hypr_text" 'hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("obsidian"))'
}

test_flake_uses_flat_nix_config_files() {
  local flake_text
  flake_text="$(<"$REPO_DIR/flake.nix")"

  assert_file_exists "$REPO_DIR/config/home.nix"
  assert_file_exists "$REPO_DIR/config/host.nix"
  assert_file_exists "$REPO_DIR/config/hardware-configuration.nix"
  assert_file_exists "$REPO_DIR/config/darwin.nix"
  assert_contains "$flake_text" "./config/home.nix"
  assert_contains "$flake_text" "./config/nixos/configuration.nix"
  assert_contains "$flake_text" "./config/darwin.nix"
  assert_contains "$flake_text" "machine = import ./config/host.nix"
  assert_contains "$flake_text" '"${machine.hostName}" = nixpkgs.lib.nixosSystem'
  assert_contains "$flake_text" "\"\${machine.username}@linux\""
  assert_not_contains "$flake_text" "\"\${machine.username}@arch\""
  assert_contains "$flake_text" "config.allowUnfree = true"
  assert_contains "$flake_text" "apps.x86_64-linux.home-manager"
  assert_contains "$flake_text" "apps.aarch64-darwin.darwin-rebuild"
  assert_contains "$flake_text" "packages.x86_64-linux.obsidian-headless"
  assert_contains "$flake_text" "devShells.x86_64-linux.default"
  assert_contains "$flake_text" "gh"
  assert_contains "$flake_text" "powershell"
  assert_not_contains "$flake_text" "config/nix/"
}

test_nixos_uses_tracked_host_config() {
  local host_text flake_text configuration_text
  host_text="$(<"$REPO_DIR/config/host.nix")"
  flake_text="$(<"$REPO_DIR/flake.nix")"
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$host_text" 'username = "quando"'
  assert_contains "$host_text" 'hostName = "nixos"'
  assert_contains "$host_text" 'timeZone = "America/Los_Angeles"'
  assert_contains "$host_text" 'stateVersion = "26.05"'
  assert_contains "$flake_text" 'nixosConfigurations = {'
  assert_contains "$configuration_text" "import ../host.nix"
  assert_not_contains "$configuration_text" "/etc/nixos/machine.nix"
}

test_darwin_uses_tracked_host_username() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$darwin_text" "machine = import ./host.nix"
  assert_contains "$darwin_text" "system.primaryUser = machine.username"
  assert_contains "$darwin_text" "users.users.\${machine.username} = {"
  assert_contains "$darwin_text" "home = \"/Users/\${machine.username}\""
  assert_contains "$darwin_text" "shell = pkgs.zsh"
  assert_contains "$darwin_text" "home-manager.users.\${machine.username}"
  assert_not_contains "$darwin_text" 'system.primaryUser = "quando"'
  assert_not_contains "$darwin_text" "users.users.quando"
  assert_not_contains "$darwin_text" "home-manager.users.quando"
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
  assert_contains "$home_text" "jujutsu"
  assert_contains "$home_text" "ripgrep"
  assert_contains "$home_text" "obsidian"
  assert_contains "$home_text" "obsidian-headless"
  assert_contains "$home_text" "    codex"
  assert_contains "$home_text" "    codebase-memory-mcp"
  assert_not_contains "$home_text" "lib.optional (pkgs ? codex)"
  assert_not_contains "$home_text" "lib.optional (pkgs ? codebase-memory-mcp)"
}

test_home_config_manages_obsidian_sync_service() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "systemd.user.services.obsidian-sync"
  assert_contains "$home_text" "pkgs.stdenv.isLinux"
  assert_contains "$home_text" "ob sync-status --path"
  assert_contains "$home_text" "ob sync --path"
  assert_contains "$home_text" "pkgs.obsidian-headless"
  assert_contains "$home_text" "pkgs.nodejs"
  assert_contains "$home_text" "ob not found; run dotfile update"
  assert_contains "$home_text" "No configured Obsidian vault found"
  assert_contains "$home_text" "Restart = \"on-failure\""
  assert_contains "$home_text" "WantedBy = [ \"default.target\" ]"
  assert_not_contains "$home_text" "home.activation.removeLegacyObsidianSyncService"
  assert_not_contains "$home_text" "rm -f \"\$HOME/.config/systemd/user/obsidian-sync.service\""
}

test_home_config_puts_shared_user_tools_in_common_packages() {
  local common_packages linux_packages
  common_packages="$(sed -n '/home.packages = with pkgs; \[/,/\] ++ lib.optionals pkgs.stdenv.isLinux \[/p' "$REPO_DIR/config/home.nix")"
  linux_packages="$(sed -n '/\] ++ lib.optionals pkgs.stdenv.isLinux \[/,/  \];/p' "$REPO_DIR/config/home.nix")"

  for pkg in ast-grep zig odin gleam erlang; do
    assert_contains "$common_packages" "$pkg"
  done
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "\"\${homeDir}/.local/bin\""
  assert_not_contains "$(<"$REPO_DIR/config/home.nix")" "GOPATH"
  assert_not_contains "$(<"$REPO_DIR/config/home.nix")" ".local/go"
  assert_not_contains "$(<"$REPO_DIR/config/home.nix")" "PNPM_HOME"
  assert_not_contains "$(<"$REPO_DIR/config/home.nix")" ".local/share/pnpm"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "nixosSystem = pkgs.stdenv.isLinux && osConfig != null"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "lib.optionals (!nixosSystem)"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "nerd-fonts.fira-code"
  assert_contains "$common_packages" "fontconfig"
  assert_contains "$common_packages" "openssh"
  assert_not_contains "$common_packages" "neovim"
  assert_not_contains "$common_packages" "gnupg"
  assert_not_contains "$common_packages" "fd"
  assert_not_contains "$common_packages" "ripgrep"
  assert_not_contains "$common_packages" "lazygit"
  assert_not_contains "$common_packages" "jujutsu"
  assert_not_contains "$common_packages" "fzf"
  assert_not_contains "$common_packages" "zoxide"
  assert_not_contains "$common_packages" "starship"
  assert_not_contains "$common_packages" "nodejs"
  assert_not_contains "$linux_packages" "nerd-fonts.fira-code"
  assert_contains "$linux_packages" "waybar"
  for pkg in lua5_1 luarocks tree-sitter unzip; do
    assert_not_contains "$common_packages" "$pkg"
    assert_not_contains "$linux_packages" "$pkg"
  done
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.neovim = {"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "defaultEditor = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "vimAlias = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "viAlias = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "withPython3 = false"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "withRuby = false"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "pkgs.vimPlugins.lazy-nvim"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "extraPackages = with pkgs; ["
  for pkg in lua5_1 luarocks tree-sitter unzip; do
    assert_contains "$(<"$REPO_DIR/config/home.nix")" "$pkg"
  done
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.gpg.enable = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.fd.enable = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.ripgrep.enable = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.lazygit.enable = true"
  assert_contains "$(<"$REPO_DIR/config/home.nix")" "programs.tmux"
}

test_nixos_system_packages_leave_user_tools_to_home_manager() {
  local packages_text
  packages_text="$(sed -n '/environment.systemPackages =/,/];/p' "$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$(<"$REPO_DIR/config/nixos/configuration.nix")" "fonts.packages = with pkgs; [ nerd-fonts.fira-code ];"
  assert_contains "$packages_text" "git"
  assert_contains "$packages_text" "jq"
  assert_contains "$packages_text" "gcc"
  assert_contains "$packages_text" "google-chrome"
  assert_contains "$packages_text" "ghostty"
  assert_not_contains "$packages_text" "lib.optional (pkgs ? ghostty)"
  assert_not_contains "$packages_text" "    zsh"
  assert_not_contains "$packages_text" "    waybar"

  for pkg in tmux neovim fzf fd ripgrep lazygit jujutsu starship zoxide gnupg wl-clipboard openssh unzip fontconfig tree-sitter nodejs lua5_1 luarocks obsidian; do
    assert_not_contains "$packages_text" "      $pkg"
  done
  assert_not_contains "$packages_text" "codex"
}

test_home_config_uses_tracked_host_username() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "machine = import ./host.nix"
  assert_contains "$home_text" "home.username = machine.username"
  assert_contains "$home_text" "\"/home/\${machine.username}\""
  assert_not_contains "$home_text" 'home.username = "quando"'
  assert_not_contains "$home_text" '"/home/quando"'
}

test_home_config_manages_gitconfig_and_starship_config() {
  local home_text zsh_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$home_text" "forceSource = source:"
  assert_contains "$home_text" "programs.git = {"
  assert_contains "$home_text" "settings = {"
  assert_contains "$home_text" "name = \"Quan Do\""
  assert_contains "$home_text" "email = \"minhquand3@gmail.com\""
  assert_contains "$home_text" "ignorecase = false"
  assert_not_contains "$home_text" "editor = \"nvim\""
  assert_contains "$home_text" "commit.gpgsign = true"
  assert_contains "$home_text" "tag.gpgsign = true"
  assert_contains "$home_text" "gpg.program = \"gpg\""
  assert_contains "$home_text" "path = \"~/.gitconfig.local\""
  assert_contains "$home_text" "path = \"~/.gitconfig.windows\""
  assert_not_contains "$home_text" "home.file.\".gitconfig\""
  assert_not_contains "$home_text" "forceSource ./shared/.gitconfig"
  assert_contains "$home_text" "force = true"
  assert_contains "$home_text" "programs.starship = {"
  assert_contains "$home_text" "enable = true"
  assert_contains "$home_text" "settings = builtins.fromTOML"
  assert_contains "$home_text" "builtins.readFile ./shared/config/starship.toml"
  assert_not_contains "$home_text" "xdg.configFile.\"starship.toml\""
  assert_not_contains "$zsh_text" "starship init zsh"
}

test_home_config_owns_remaining_dotfiles() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_not_contains "$home_text" "home.file.\".vimrc\""
  assert_not_contains "$home_text" "forceSource ./shared/.vimrc"
  assert_not_contains "$home_text" "home.file.\".tmux.conf\""
  assert_not_contains "$home_text" "home.file.\".zprofile\""
  assert_not_contains "$home_text" "forceSource ./unix/.zprofile"
  assert_not_contains "$home_text" "home.file.\".zshrc.base\""
  assert_not_contains "$home_text" "forceSource ./unix/.zshrc.base"
  assert_not_contains "$home_text" "home.file.\".zshrc\""
  assert_contains "$home_text" "initContent = lib.mkOrder 550 (builtins.readFile ./unix/.zshrc.base)"
  assert_not_contains "$home_text" "source \"\$HOME/.zshrc.base\""
  assert_contains "$home_text" "\".ssh/config\" = forceSource ./shared/.ssh/config"
  assert_contains "$home_text" "forceSource ./shared/.ssh/config"
  assert_contains "$home_text" "\".claude/settings.json\" = forceSource ./shared/ai/claude/settings.json"
  assert_contains "$home_text" "forceSource ./shared/ai/claude/settings.json"
  assert_not_contains "$home_text" "home.file.\".codex/config.toml\""
  assert_contains "$home_text" "home.activation.seedCodexConfig"
  assert_contains "$home_text" "cp \"\$source\" \"\$target\""
  assert_contains "$home_text" "cavemanSrc = pkgs.fetchFromGitHub"
  assert_contains "$home_text" "owner = \"JuliusBrussee\""
  assert_contains "$home_text" "repo = \"caveman\""
  assert_contains "$home_text" "\".codex/skills/caveman/SKILL.md\" = forceSource \"\${cavemanSrc}/skills/caveman/SKILL.md\""
  assert_not_contains "$home_text" ".agents/skills/caveman"
  assert_contains "$home_text" "obsidianSettings = ["
  assert_contains "$home_text" "\"app.json\""
  assert_contains "$home_text" "\"documents/Sync/.obsidian/\${name}\""
  assert_contains "$home_text" "forceSource ./shared/obsidian/\${name}"
  assert_contains "$home_text" "\".local/bin/dotfile\" = {"
  assert_not_contains "$home_text" "\".local/bin/dotfile\" = lib.mkIf pkgs.stdenv.isLinux"
  assert_contains "$home_text" "dotfiles_dir=\"''\${DOTFILES_DIR:-\$HOME/dotfiles}\""
  assert_contains "$home_text" 'exec "$dotfiles_dir/dotfile" "$@"'
  assert_not_contains "$home_text" "\".zshrc.mac\""
  assert_not_contains "$home_text" "forceSource ./mac/.zshrc.mac"
  assert_contains "$home_text" "\".local/bin/caf\" = lib.mkIf pkgs.stdenv.isDarwin"
  assert_contains "$home_text" "forceSource ./mac/bin/caf"
  assert_contains "$home_text" "pkgs.stdenv.isDarwin"
}

test_darwin_config_manages_core_packages() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$darwin_text" "nix.settings.experimental-features"
  assert_contains "$darwin_text" "nixpkgs.config.allowUnfree = true"
  assert_contains "$darwin_text" "environment.systemPackages"
  assert_contains "$darwin_text" "bash"
  assert_contains "$darwin_text" "git"
  assert_contains "$darwin_text" "programs.zsh.enable = true"
  assert_contains "$darwin_text" "system.primaryUser = machine.username"
}

test_darwin_system_packages_leave_user_tools_to_home_manager() {
  local packages_text
  packages_text="$(sed -n '/environment.systemPackages =/,/\];/p' "$REPO_DIR/config/darwin.nix")"

  assert_contains "$packages_text" "bash"
  assert_contains "$packages_text" "git"
  for pkg in tmux neovim fzf fd ripgrep gnupg lazygit zoxide jujutsu starship nodejs ast-grep; do
    assert_not_contains "$packages_text" "    $pkg"
  done
}

test_home_config_uses_home_manager_zsh_plugins() {
  local home_text zsh_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$home_text" "programs.zsh = {"
  assert_contains "$home_text" "enable = true"
  assert_not_contains "$home_text" "brew shellenv"
  assert_not_contains "$home_text" "/opt/homebrew/bin/brew"
  assert_not_contains "$home_text" "/usr/local/bin/brew"
  assert_contains "$home_text" "enableCompletion = true"
  assert_contains "$home_text" "completionInit = ''"
  assert_contains "$home_text" "_zcompdump="
  assert_contains "$home_text" "compinit -d \"\$_zcompdump\""
  assert_contains "$home_text" "compinit -C -d \"\$_zcompdump\""
  assert_contains "$home_text" "zstyle ':completion:*' matcher-list"
  assert_contains "$home_text" "defaultKeymap = \"viins\""
  assert_contains "$home_text" "history = {"
  assert_contains "$home_text" "size = 50000"
  assert_contains "$home_text" "save = 10000"
  assert_contains "$home_text" "setOptions = [ \"INC_APPEND_HISTORY\" \"HIST_VERIFY\" ]"
  assert_contains "$home_text" "autosuggestion.enable = true"
  assert_contains "$home_text" "fastSyntaxHighlighting.enable = true"
  assert_contains "$home_text" "plugins = ["
  assert_contains "$home_text" "pkgs.zsh-fzf-tab"
  assert_not_contains "$home_text" "xdg.dataFile.\"zsh/plugins"
  assert_not_contains "$zsh_text" "export SHELL="
  assert_not_contains "$zsh_text" "export EDITOR=nvim"
  assert_not_contains "$zsh_text" "alias vim=nvim"
  assert_not_contains "$zsh_text" "/opt/nvim-linux-x86_64"
  assert_not_contains "$zsh_text" "HYPRSHOT_DIR"
  assert_not_contains "$zsh_text" "hyprshot"
  assert_not_contains "$zsh_text" "GOPATH"
  assert_not_contains "$zsh_text" "GOBIN"
  assert_not_contains "$zsh_text" "PNPM_HOME"
  assert_not_contains "$zsh_text" "\$HOME/.local/bin"
  assert_not_contains "$zsh_text" ".opencode/bin"
  assert_not_contains "$zsh_text" ".bun/bin"
  assert_not_contains "$zsh_text" "/snap/bin"
  assert_not_contains "$zsh_text" ".devcontainers/bin"
  assert_not_contains "$zsh_text" "LESS_TERMCAP"
  assert_not_contains "$zsh_text" "_zsh_plugins="
  assert_not_contains "$zsh_text" "zsh-autosuggestions.zsh"
  assert_not_contains "$zsh_text" "fast-syntax-highlighting.plugin.zsh"
  assert_not_contains "$zsh_text" "fzf-tab.plugin.zsh"
  assert_not_contains "$zsh_text" "HISTFILE="
  assert_not_contains "$zsh_text" "HISTSIZE="
  assert_not_contains "$zsh_text" "SAVEHIST="
  assert_not_contains "$zsh_text" "setopt append_history"
  assert_not_contains "$zsh_text" "bindkey -v"
  assert_not_contains "$zsh_text" "autoload -Uz compinit"
  assert_not_contains "$zsh_text" "_zcompdump="
  assert_not_contains "$zsh_text" "compinit -d"
  assert_not_contains "$zsh_text" "compinit -C"
  assert_not_contains "$zsh_text" "zstyle ':completion:*' matcher-list"
  assert_not_contains "$zsh_text" ".zshrc.mac"
  assert_contains "$home_text" "programs.zoxide = {"
  assert_contains "$home_text" "enableZshIntegration = true"
  assert_contains "$home_text" "options = [ \"--cmd\" \"cd\" ]"
  assert_not_contains "$zsh_text" "zoxide init zsh"
  assert_not_contains "$zsh_text" "_ZO_DOCTOR"
  assert_contains "$home_text" "programs.fzf = {"
  assert_contains "$home_text" "enableZshIntegration = true"
  assert_not_contains "$zsh_text" "fzf --zsh"
  assert_contains "$home_text" "programs.jujutsu = {"
  assert_contains "$home_text" "settings = builtins.fromTOML"
  assert_contains "$home_text" "builtins.readFile ./shared/config/jj/config.toml"
  assert_not_contains "$zsh_text" "COMPLETE=zsh jj"
}

test_zsh_arrow_keys_search_history_by_prefix() {
  local zsh_text
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$zsh_text" "bindkey -M viins '^[[A' history-beginning-search-backward"
  assert_contains "$zsh_text" "bindkey -M viins '^[[B' history-beginning-search-forward"
  assert_contains "$zsh_text" "bindkey -M viins '^[OA' history-beginning-search-backward"
  assert_contains "$zsh_text" "bindkey -M viins '^[OB' history-beginning-search-forward"
}

test_home_config_uses_home_manager_tmux_plugins() {
  local home_text tmux_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  tmux_text="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_contains "$home_text" "programs.tmux = {"
  assert_contains "$home_text" "enable = true"
  assert_contains "$home_text" "plugins = ["
  assert_contains "$home_text" "pkgs.tmuxPlugins.yank"
  assert_contains "$home_text" "pkgs.tmuxPlugins.catppuccin"
  assert_contains "$home_text" "extraConfig = builtins.readFile ./unix/.tmux.conf"
  assert_not_contains "$home_text" "home.file.\".tmux/plugins"
  assert_not_contains "$tmux_text" "run ~/.tmux/plugins"
}

test_home_config_owns_existing_xdg_configs() {
  local home_text lazy_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  lazy_text="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/lazy.lua")"

  assert_not_contains "$home_text" "xdg.configFile.\"jj\""
  assert_contains "$home_text" "xdg.configFile.\"nvim\""
  assert_contains "$home_text" "./shared/config/nvim"
  assert_not_contains "$(<"$REPO_DIR/config/shared/config/nvim/init.lua")" "bootstrap lazy.nvim"
  assert_not_contains "$lazy_text" "lazyrepo"
  assert_not_contains "$lazy_text" "git\", \"clone"
  assert_not_contains "$lazy_text" "enabled = true, -- check for plugin updates"
  assert_not_contains "$lazy_text" "latest git commit"
  assert_contains "$lazy_text" "run dotfile update"
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

test_doctor_paths_cover_home_manager_managed_paths() {
  local doctor_text home_text manifest_text path
  home_text="$(<"$REPO_DIR/config/home.nix")"
  doctor_text="$(<"$REPO_DIR/scripts/doctor.sh")"
  if [[ -e "$REPO_DIR/config/home-manager-managed-paths" ]]; then
    echo "  FAILED: Home Manager paths should be declared only in config/home.nix" >> "$ERROR_FILE"
  fi
  assert_not_contains "$doctor_text" "home-manager-managed-paths"
  assert_not_contains "$doctor_text" "_read_home_manager_managed_paths()"
  assert_not_contains "$doctor_text" "  .gitconfig"
  assert_not_contains "$doctor_text" "  .vimrc"
  assert_not_contains "$doctor_text" "  .zprofile"
  assert_not_contains "$doctor_text" "  .zshrc.base"
  assert_not_contains "$doctor_text" "REQUIRED_SYMLINKS=(.zshrc .zshrc.base .tmux.conf .vimrc .gitconfig .zprofile)"
  assert_not_contains "$doctor_text" "_doctor_check_managed_paths"
  assert_not_contains "$home_text" 'home.file.".codex/config.toml"'
}
