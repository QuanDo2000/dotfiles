{ pkgs, lib, ... }:

let
  machine = import ./host.nix;
  homeDir =
    if pkgs.stdenv.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
  obsidianSync = pkgs.writeShellScript "obsidian-sync" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.obsidian-headless pkgs.nodejs ]}:$PATH"

    if ! command -v ob >/dev/null 2>&1; then
      echo "ob not found; run dotfile update to install obsidian-headless" >&2
      exit 0
    fi

    shopt -s nullglob
    for vault in "$HOME"/documents/obsidian/*; do
      if [ -d "$vault" ] && ob sync-status --path "$vault" >/dev/null 2>&1; then
        exec ob sync --path "$vault" --continuous
      fi
    done

    echo "No configured Obsidian vault found under $HOME/documents/obsidian" >&2
    exit 0
  '';
in
{
  home.username = machine.username;
  home.homeDirectory = homeDir;
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    neovim
    tmux
    fzf
    fd
    ripgrep
    lazygit
    zoxide
    gnupg
    nodejs
    jujutsu
    starship
    ast-grep
    zig
    odin
    gleam
    beamPackages.erlang
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    fontconfig
    nerd-fonts.fira-code
    wl-clipboard
    openssh
    lua5_1
    luarocks
    tree-sitter
    unzip
    obsidian
    obsidian-headless
  ]
  ++ lib.optional (pkgs ? codex) pkgs.codex
  ++ lib.optional (pkgs ? codebase-memory-mcp) pkgs.codebase-memory-mcp;

  home.file.".gitconfig" = {
    source = ./shared/.gitconfig;
    force = true;
  };

  home.file.".vimrc" = {
    source = ./shared/.vimrc;
    force = true;
  };

  home.file.".tmux.conf" = {
    source = ./unix/.tmux.conf;
    force = true;
  };

  home.file.".zprofile" = {
    source = ./unix/.zprofile;
    force = true;
  };

  home.file.".zshrc.base" = {
    source = ./unix/.zshrc.base;
    force = true;
  };

  home.file.".zshrc" = {
    text = ''
      [ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"
    '';
    force = true;
  };

  home.file.".ssh/config" = {
    source = ./shared/.ssh/config;
    force = true;
  };

  home.file.".claude/settings.json" = {
    source = ./shared/ai/claude/settings.json;
    force = true;
  };

  home.file.".tmux/plugins/tmux-yank" = {
    source = "${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank";
    force = true;
  };

  home.file.".tmux/plugins/catppuccin/tmux" = {
    source = "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";
    force = true;
  };

  programs.home-manager.enable = true;

  systemd.user.services.obsidian-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Obsidian Sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${obsidianSync}";
      Restart = "on-failure";
      RestartSec = 10;
    };

    Install.WantedBy = [ "default.target" ];
  };

  home.activation.seedCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.codex/config.toml"
    source="${./shared/ai/codex/config.toml}"
    replace=false

    if [ ! -e "$target" ]; then
      replace=true
    elif [ -L "$target" ]; then
      case "$(readlink "$target")" in
        /nix/store/*) replace=true ;;
      esac
    fi

    if [ "$replace" = true ]; then
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      cp "$source" "$target"
      chmod u+w "$target"
    fi
  '';

  xdg.configFile."starship.toml" = {
    source = ./shared/config/starship.toml;
    force = true;
  };

  xdg.configFile."jj" = {
    source = ./shared/config/jj;
    force = true;
  };

  xdg.configFile."nvim" = {
    source = ./shared/config/nvim;
    force = true;
  };

  xdg.configFile."fcitx5" = {
    source = ./unix/config/fcitx5;
    force = true;
  };

  xdg.configFile."ghostty/config" = {
    source = ./unix/config/ghostty/config;
    force = true;
  };

  xdg.configFile."hypr" = {
    source = ./unix/config/hypr;
    force = true;
  };

  xdg.configFile."waybar" = {
    source = ./unix/config/waybar;
    force = true;
  };

  xdg.dataFile."zsh/plugins/zsh-autosuggestions" = {
    source = "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";
    force = true;
  };

  xdg.dataFile."zsh/plugins/fast-syntax-highlighting" = {
    source = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";
    force = true;
  };

  xdg.dataFile."zsh/plugins/fzf-tab" = {
    source = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
    force = true;
  };

  home.file.".local/bin/dotfile" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      #!/usr/bin/env bash
      exec "$HOME/dotfiles/dotfile" "$@"
    '';
    executable = true;
    force = true;
  };

  home.file.".zshrc.mac" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./mac/.zshrc.mac;
    force = true;
  };

  home.file.".local/bin/caf" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./mac/bin/caf;
    executable = true;
    force = true;
  };
}
