{ pkgs, lib, osConfig ? null, ... }:

let
  machine = import ./host.nix;
  nixosSystem = pkgs.stdenv.isLinux && osConfig != null;
  standaloneLinux = pkgs.stdenv.isLinux && !nixosSystem;
  homeDir =
    if pkgs.stdenv.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
  forceSource = source: {
    inherit source;
    force = true;
  };
  linuxConfig = source: lib.mkIf pkgs.stdenv.isLinux (forceSource source);
  cavemanSrc = pkgs.fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "0d95a81d35a9f2d123a5e9430d1cfc43d55f1bb0";
    hash = "sha256-VqRHx3/4SSCnEh3cUJ/he5saIfwNhS0hOzoH/wwtU2o=";
  };
  superpowersSrc = pkgs.fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "c984ea2e7aeffdcc865784fd6c5e3ab75da0209a";
    hash = "sha256-kHdQ9e44doBk2yYW88tMSCqVG8ycYcvJSZlrIziXhpA=";
  };
  pi-agent = pkgs.callPackage ../packages/pi-agent.nix { };
  obsidianSettings = [
    "app.json"
    "appearance.json"
    "community-plugins.json"
    "core-plugins.json"
    "daily-notes.json"
    "hotkeys.json"
    "plugins/calendar/data.json"
    "plugins/dataview/data.json"
    "plugins/obsidian-linter/data.json"
    "plugins/obsidian-minimal-settings/data.json"
    "plugins/obsidian-style-settings/data.json"
    "plugins/obsidian-tasks-plugin/data.json"
    "plugins/obsidian-vimrc-support/data.json"
    "plugins/periodic-notes/data.json"
    "plugins/table-editor-obsidian/data.json"
    "templates.json"
  ];
  obsidianFiles = lib.genAttrs
    (map (name: "documents/obsidian/Sync/.obsidian/${name}") obsidianSettings)
    (path: forceSource (./shared/obsidian + "/${lib.removePrefix "documents/obsidian/Sync/.obsidian/" path}"));
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
  devTerminalPackages = with pkgs; [
    ast-grep
    codex
    codebase-memory-mcp
    jq
    pi-agent
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    gcc
  ];
  standaloneLinuxPackages = with pkgs; [
    fontconfig
    openssh
  ];
  linuxDesktopPackages = with pkgs; [
    wl-clipboard
    waybar
    ghostty
    google-chrome
    obsidian
    obsidian-headless
  ];
in
{
  home.username = machine.username;
  home.homeDirectory = homeDir;
  home.stateVersion = "24.11";
  home.sessionPath = [
    "${homeDir}/.local/bin"
  ];
  home.packages = devTerminalPackages
  ++ lib.optionals (!nixosSystem) [
    pkgs.nerd-fonts.fira-code
  ]
  ++ lib.optionals standaloneLinux standaloneLinuxPackages
  ++ lib.optionals pkgs.stdenv.isLinux linuxDesktopPackages;

  home.file = obsidianFiles // {
    ".ssh/config" = forceSource ./shared/.ssh/config;
    ".claude/settings.json" = forceSource ./shared/ai/claude/settings.json;
    ".codex/skills/caveman/README.md" = forceSource "${cavemanSrc}/skills/caveman/README.md";
    ".codex/skills/caveman/SKILL.md" = forceSource "${cavemanSrc}/skills/caveman/SKILL.md";
    ".codex/skills/systematic-debugging" = forceSource "${superpowersSrc}/skills/systematic-debugging";
    ".codex/skills/test-driven-development" = forceSource "${superpowersSrc}/skills/test-driven-development";
    ".codex/skills/verification-before-completion" = forceSource "${superpowersSrc}/skills/verification-before-completion";
    ".pi/agent/extensions/codebase-memory-guidance.ts" = forceSource ./shared/ai/pi/codebase-memory-guidance.ts;
    ".pi/agent/extensions/codex-status.js" = forceSource ./shared/ai/pi/codex-status.js;
    ".local/bin/dotfile" = {
      text = ''
        #!/usr/bin/env bash
        dotfiles_dir="''${DOTFILES_DIR:-$HOME/dotfiles}"
        exec "$dotfiles_dir/dotfile" "$@"
      '';
      executable = true;
      force = true;
    };
    ".local/bin/caf" = lib.mkIf pkgs.stdenv.isDarwin (forceSource ./mac/bin/caf // {
      executable = true;
    });
  };

  programs.home-manager.enable = true;

  programs.gpg.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    withPython3 = false;
    withRuby = false;
    plugins = [ pkgs.vimPlugins.lazy-nvim ];
    extraPackages = with pkgs; [
      lua5_1
      luarocks
      tree-sitter
      unzip
    ];
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Quan Do";
        email = "minhquand3@gmail.com";
      };
      core = {
        ignorecase = false;
      };
      commit.gpgsign = true;
      tag.gpgsign = true;
      gpg.program = "gpg";
    };
    includes = [
      { path = "~/.gitconfig.local"; }
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
    initContent = lib.mkOrder 550 (builtins.readFile ./unix/.zshrc.base);
    completionInit = ''
      () {
        setopt local_options extended_glob
        autoload -Uz compinit
        _zcompdump="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
        mkdir -p "''${_zcompdump:h}"
        if [[ ! -f "$_zcompdump" || -n "$_zcompdump"(#qN.mh+24) ]]; then
          compinit -d "$_zcompdump"
        else
          compinit -C -d "$_zcompdump"
        fi
      }

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
    repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/ai/codex/config.toml"
    apply_seed=
    replace=false

    if [ ! -e "$target" ]; then
      replace=true
    elif [ -L "$target" ]; then
      case "$(readlink "$target")" in
        /nix/store/*) replace=true ;;
      esac
    fi

    if [ -f "$target" ] && [ ! -L "$target" ]; then
      if [ -w "$repo_seed" ]; then
        apply_seed="$repo_seed"
      fi

      "${pkgs.python3}/bin/python3" "${../scripts/codex_seed_merge.py}" "$target" "$source" "$apply_seed" || echo "Warning: failed to sync Codex config seed" >&2
    fi

    if [ "$replace" = true ]; then
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      cp "$source" "$target"
      chmod u+w "$target"
    fi
  '';

  home.activation.seedPiSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.pi/agent/settings.json"
    source="${./shared/ai/pi/settings.json}"
    repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/ai/pi/settings.json"
    apply_seed=

    mkdir -p "$(dirname "$target")"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      if [ -w "$repo_seed" ]; then
        apply_seed="$repo_seed"
      fi
      "${pkgs.python3}/bin/python3" "${../scripts/pi_seed_merge.py}" "$target" "$source" "$apply_seed" || echo "Warning: failed to sync Pi settings seed" >&2
      merge_source="''${apply_seed:-$source}"
      merged="$(mktemp)"
      "${pkgs.jq}/bin/jq" -s '.[0] * .[1]' "$target" "$merge_source" > "$merged"
      mv "$merged" "$target"
    else
      rm -f "$target"
      cp "$source" "$target"
    fi
    chmod u+w "$target"
  '';

  home.activation.seedPiMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.pi/agent/mcp.json"
    source="${./shared/ai/pi/mcp.json}"
    repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/ai/pi/mcp.json"
    apply_seed=

    mkdir -p "$(dirname "$target")"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      if [ -w "$repo_seed" ]; then
        apply_seed="$repo_seed"
      fi
      "${pkgs.python3}/bin/python3" "${../scripts/pi_seed_merge.py}" "$target" "$source" "$apply_seed" || echo "Warning: failed to sync Pi MCP config seed" >&2
      merge_source="''${apply_seed:-$source}"
      merged="$(mktemp)"
      "${pkgs.jq}/bin/jq" -s '.[0] * .[1]' "$target" "$merge_source" > "$merged"
      mv "$merged" "$target"
    else
      rm -f "$target"
      cp "$source" "$target"
    fi
    chmod u+w "$target"
  '';

  xdg.configFile."nvim" = forceSource ./shared/config/nvim;

  xdg.configFile."fcitx5" = linuxConfig ./unix/config/fcitx5;

  xdg.configFile."ghostty/config" = forceSource ./unix/config/ghostty/config;

  xdg.configFile."hypr" = linuxConfig ./unix/config/hypr;

  xdg.configFile."waybar" = linuxConfig ./unix/config/waybar;

}
