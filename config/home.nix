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
    gnupg
    nodejs
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

  home.file.".vimrc" = forceSource ./shared/.vimrc;

  home.file.".zprofile" = forceSource ./unix/.zprofile;

  home.file.".zshrc.base" = forceSource ./unix/.zshrc.base;

  home.file.".ssh/config" = forceSource ./shared/.ssh/config;

  home.file.".claude/settings.json" = forceSource ./shared/ai/claude/settings.json;

  home.file."documents/Sync/.obsidian/app.json" = forceSource ./shared/obsidian/app.json;

  home.file."documents/Sync/.obsidian/appearance.json" = forceSource ./shared/obsidian/appearance.json;

  home.file."documents/Sync/.obsidian/community-plugins.json" = forceSource ./shared/obsidian/community-plugins.json;

  home.file."documents/Sync/.obsidian/core-plugins.json" = forceSource ./shared/obsidian/core-plugins.json;

  home.file."documents/Sync/.obsidian/daily-notes.json" = forceSource ./shared/obsidian/daily-notes.json;

  home.file."documents/Sync/.obsidian/hotkeys.json" = forceSource ./shared/obsidian/hotkeys.json;

  home.file."documents/Sync/.obsidian/templates.json" = forceSource ./shared/obsidian/templates.json;

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Quan Do";
        email = "minhquand3@gmail.com";
      };
      core = {
        ignorecase = false;
        editor = "nvim";
      };
      commit.gpgsign = true;
      tag.gpgsign = true;
      gpg.program = "gpg";
    };
    includes = [
      { path = "~/.gitconfig.local"; }
      { path = "~/.gitconfig.windows"; }
    ];
  };

  programs.starship = {
    enable = true;
    settings = builtins.fromTOML (builtins.readFile ./shared/config/starship.toml);
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd" "cd" ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.jujutsu = {
    enable = true;
    settings = builtins.fromTOML (builtins.readFile ./shared/config/jj/config.toml);
  };

  programs.lazygit.enable = true;

  programs.ripgrep.enable = true;

  programs.fd.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    defaultKeymap = "viins";
    history = {
      append = true;
      size = 50000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };
    setOptions = [ "INC_APPEND_HISTORY" "HIST_VERIFY" ];
    initContent = lib.mkOrder 550 ''
      [ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"
    '';
    completionInit = ''
      autoload -Uz compinit
      _zcompdump="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
      mkdir -p "''${_zcompdump:h}"
      if [[ ! -f "$_zcompdump" || -n "$_zcompdump"(#qN.mh+24) ]]; then
        compinit -d "$_zcompdump"
      else
        compinit -C -d "$_zcompdump"
      fi

      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'l:|=* r:|=*'
    '';
    autosuggestion.enable = true;
    fastSyntaxHighlighting.enable = true;
    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    mouse = true;
    focusEvents = true;
    aggressiveResize = true;
    escapeTime = 10;
    historyLimit = 50000;
    plugins = [
      {
        plugin = pkgs.tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor 'macchiato'
          set -g @catppuccin_window_status_style 'basic'
          set -g @catppuccin_window_text ' #{b:pane_current_command}'
          set -g @catppuccin_window_current_text ' #{b:pane_current_command}'
          set -g @catppuccin_status_background 'none'
          set -g @catppuccin_date_time_text ' %Y-%m-%d %H:%M:%S'
        '';
      }
      pkgs.tmuxPlugins.yank
    ];
    extraConfig = builtins.readFile ./unix/.tmux.conf;
  };

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

  xdg.configFile."nvim" = forceSource ./shared/config/nvim;

  xdg.configFile."fcitx5" = forceSource ./unix/config/fcitx5;

  xdg.configFile."ghostty/config" = forceSource ./unix/config/ghostty/config;

  xdg.configFile."hypr" = forceSource ./unix/config/hypr;

  xdg.configFile."waybar" = forceSource ./unix/config/waybar;

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
