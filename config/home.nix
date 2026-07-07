{ pkgs, lib, ... }:

let
  machine = import ./host.nix;
  homeDir =
    if pkgs.stdenv.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
  forceSource = source: {
    inherit source;
    force = true;
  };
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

  home.file.".gitconfig" = forceSource ./shared/.gitconfig;

  home.file.".vimrc" = forceSource ./shared/.vimrc;

  home.file.".tmux.conf" = forceSource ./unix/.tmux.conf;

  home.file.".zprofile" = forceSource ./unix/.zprofile;

  home.file.".zshrc.base" = forceSource ./unix/.zshrc.base;

  home.file.".zshrc" = {
    text = ''
      [ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"
    '';
    force = true;
  };

  home.file.".ssh/config" = forceSource ./shared/.ssh/config;

  home.file.".claude/settings.json" = forceSource ./shared/ai/claude/settings.json;

  home.file."documents/Sync/.obsidian/app.json" = forceSource ./shared/obsidian/app.json;

  home.file."documents/Sync/.obsidian/appearance.json" = forceSource ./shared/obsidian/appearance.json;

  home.file."documents/Sync/.obsidian/community-plugins.json" = forceSource ./shared/obsidian/community-plugins.json;

  home.file."documents/Sync/.obsidian/core-plugins.json" = forceSource ./shared/obsidian/core-plugins.json;

  home.file."documents/Sync/.obsidian/daily-notes.json" = forceSource ./shared/obsidian/daily-notes.json;

  home.file."documents/Sync/.obsidian/hotkeys.json" = forceSource ./shared/obsidian/hotkeys.json;

  home.file."documents/Sync/.obsidian/templates.json" = forceSource ./shared/obsidian/templates.json;

  home.file.".tmux/plugins/tmux-yank" = forceSource "${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank";

  home.file.".tmux/plugins/catppuccin/tmux" = forceSource "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";

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

  xdg.configFile."starship.toml" = forceSource ./shared/config/starship.toml;

  xdg.configFile."jj" = forceSource ./shared/config/jj;

  xdg.configFile."nvim" = forceSource ./shared/config/nvim;

  xdg.configFile."fcitx5" = forceSource ./unix/config/fcitx5;

  xdg.configFile."ghostty/config" = forceSource ./unix/config/ghostty/config;

  xdg.configFile."hypr" = forceSource ./unix/config/hypr;

  xdg.configFile."waybar" = forceSource ./unix/config/waybar;

  xdg.dataFile."zsh/plugins/zsh-autosuggestions" = forceSource "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";

  xdg.dataFile."zsh/plugins/fast-syntax-highlighting" = forceSource "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";

  xdg.dataFile."zsh/plugins/fzf-tab" = forceSource "${pkgs.zsh-fzf-tab}/share/fzf-tab";

  home.file.".local/bin/dotfile" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      #!/usr/bin/env bash
      exec "$HOME/dotfiles/dotfile" "$@"
    '';
    executable = true;
    force = true;
  };

  home.file.".zshrc.mac" = lib.mkIf pkgs.stdenv.isDarwin (forceSource ./mac/.zshrc.mac);

  home.file.".local/bin/caf" = lib.mkIf pkgs.stdenv.isDarwin (forceSource ./mac/bin/caf // {
    executable = true;
  });
}
