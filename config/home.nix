{ pkgs, lib, osConfig ? null, ... }:

let
  machine = import ./host.nix;
  nixosSystem = pkgs.stdenv.isLinux && osConfig != null;
  standaloneLinux = pkgs.stdenv.isLinux && !nixosSystem;
  homeDir =
    if pkgs.stdenv.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
  psCommand = if pkgs.stdenv.isDarwin then "/bin/ps" else "${pkgs.procps}/bin/ps";
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
  ankiWithAddons = pkgs.anki.withAddons [
    (pkgs.ankiAddons.passfail2.withConfig {
      config = {
        toggle_names_textcolors = "0";
        again_button_name = "Fail";
        good_button_name = "Pass";
        again_button_textcolor = "#000000";
        good_button_textcolor = "#000000";
      };
    })
    ((pkgs.anki-utils.buildAnkiAddon {
      pname = "zoom24";
      version = "2026-05-27";
      src = pkgs.fetchzip {
        url = "https://ankiweb.net/shared/download/1923741581?v=2.1&p=2509004";
        hash = "sha256-6dRKLIc/ySELmOI8xHkSZO2orTZSHb7e12aL2pSogfY=";
        extension = "zip";
        stripRoot = false;
      };
    }).withConfig {
      config = {
        overview_zoom = 1.0;
        overview_zoom_default = 1.0;
        review_zoom = 1.0;
        review_zoom_default = 1.0;
        zoom_in_shortcut = "Ctrl+Shift++";
        zoom_out_shortcut = "Ctrl+Shift+-";
        reset_shortcut = "Ctrl+Shift+^";
        manually_force_zoom = false;
        different_zoom_question_and_answer = true;
        is_rate_this = true;
        is_change_log_2024_2_21 = true;
      };
    })
  ];
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
    (map (name: "Documents/obsidian/Sync/.obsidian/${name}") obsidianSettings)
    (path: forceSource (./shared/obsidian + "/${lib.removePrefix "Documents/obsidian/Sync/.obsidian/" path}"));
  obsidianSync = pkgs.writeShellScript "obsidian-sync" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.obsidian-headless pkgs.nodejs ]}:$PATH"

    if ! command -v ob >/dev/null 2>&1; then
      echo "ob not found; run dotfile update to install obsidian-headless" >&2
      exit 0
    fi

    shopt -s nullglob
    for vault in "$HOME"/Documents/obsidian/*; do
      if [ -d "$vault" ] && ob sync-status --path "$vault" >/dev/null 2>&1; then
        exec ob sync --path "$vault" --continuous
      fi
    done

    echo "No configured Obsidian vault found under $HOME/Documents/obsidian" >&2
    exit 0
  '';
  devTerminalPackages = with pkgs; [
    ast-grep
    codex
    codebase-memory-mcp
    fff-mcp
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
    ankiWithAddons
    grim
    pinentry-gnome3
    rbw
    rofi-rbw
    slurp
    thunar
    wl-clipboard
    wtype
    xarchiver
    hyprshutdown
    ghostty
    google-chrome
    obsidian
    obsidian-headless
    pavucontrol
    playerctl
    webcord
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
    "${homeDir}/.config/jj/config.toml".force = true;
    ".ssh/config" = forceSource ./shared/.ssh/config;
    ".claude/settings.json" = forceSource ./shared/ai/claude/settings.json;
    ".codex/AGENTS.md" = forceSource ./shared/ai/AGENTS.md;
    ".pi/agent/AGENTS.md" = forceSource ./shared/ai/AGENTS.md;
    ".agents/skills/caveman/README.md" = forceSource "${cavemanSrc}/skills/caveman/README.md";
    ".agents/skills/caveman/SKILL.md" = forceSource "${cavemanSrc}/skills/caveman/SKILL.md";
    ".agents/skills/systematic-debugging" = forceSource "${superpowersSrc}/skills/systematic-debugging";
    ".agents/skills/test-driven-development" = forceSource "${superpowersSrc}/skills/test-driven-development";
    ".agents/skills/verification-before-completion" = forceSource "${superpowersSrc}/skills/verification-before-completion";
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

  xdg.configFile."rofi-rbw.rc".text = lib.mkIf pkgs.stdenv.isLinux ''
    selector=fuzzel
    clipboarder=wl-copy
    typer=wtype
    prompt=
    selector-args=--prompt "" --placeholder "Search vault…" --inner-pad 8
    action=copy
    target=menu
    clear-after=30
    no-cache=true
  '';

  gtk = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    gtk3.extraConfig.gtk-tooltip-timeout = 200;
  };

  xdg.configFile."mimeapps.list".force = lib.mkIf pkgs.stdenv.isLinux true;
  xdg.dataFile."applications/mimeapps.list".force = lib.mkIf pkgs.stdenv.isLinux true;

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "x-scheme-handler/http" = [ "google-chrome.desktop" ];
      "x-scheme-handler/https" = [ "google-chrome.desktop" ];
      "text/html" = [ "google-chrome.desktop" ];
      "application/zip" = [ "xarchiver.desktop" ];
      "application/x-7z-compressed" = [ "xarchiver.desktop" ];
      "application/vnd.rar" = [ "xarchiver.desktop" ];
      "application/x-rar" = [ "xarchiver.desktop" ];
      "application/x-tar" = [ "xarchiver.desktop" ];
      "application/gzip" = [ "xarchiver.desktop" ];
      "application/x-bzip2" = [ "xarchiver.desktop" ];
      "application/x-xz" = [ "xarchiver.desktop" ];
      "application/zstd" = [ "xarchiver.desktop" ];
    };
  };

  xdg.userDirs = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    setSessionVariables = false;
    documents = "${homeDir}/Documents";
    download = "${homeDir}/Downloads";
    desktop = null;
    music = null;
    pictures = null;
    projects = null;
    publicShare = null;
    templates = null;
    videos = null;
  };

  programs.fuzzel = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    settings = {
      main = {
        terminal = "ghostty";
        launch-prefix = "uwsm app --";
        layer = "overlay";
        width = 40;
        lines = 10;
        font = "FiraCode Nerd Font:size=14";
      };
      colors = {
        background = "11111be6";
        text = "cdd6f4ff";
        match = "89b4faff";
        selection = "313244ff";
        selection-text = "cdd6f4ff";
        selection-match = "89b4faff";
        border = "89b4faff";
      };
      border = {
        width = 1;
        radius = 0;
      };
    };
  };

  programs.waybar = {
    enable = pkgs.stdenv.isLinux;
    systemd.enable = pkgs.stdenv.isLinux;
  };

  programs.hyprlock.enable = pkgs.stdenv.isLinux;
  services.hypridle.enable = pkgs.stdenv.isLinux;
  services.hyprpolkitagent.enable = pkgs.stdenv.isLinux;

  services.hyprsunset.enable = pkgs.stdenv.isLinux;
  systemd.user.services.hyprsunset.Unit.X-Restart-Triggers =
    lib.mkIf pkgs.stdenv.isLinux [ "${./unix/config/hypr/hyprsunset.conf}" ];

  services.wl-clip-persist = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    clipboardType = "regular";
  };

  services.mako = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    settings = {
      output = "DP-3";
      anchor = "top-right";
      outer-margin = "45,10,10";
      margin = 5;
      padding = 12;
      width = 360;
      max-visible = 3;
      default-timeout = 5000;
      font = "FiraCode Nerd Font 14";
      background-color = "#11111be6";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 1;
      border-radius = 0;
      icons = true;
      max-icon-size = 48;
      actions = true;
      markup = true;
      "urgency=high" = {
        border-color = "#f38ba8";
        default-timeout = 0;
      };
    };
  };

  programs.gpg.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    withPython3 = false;
    withRuby = false;
    plugins = [ pkgs.vimPlugins.lazy-nvim ];
    initLua = builtins.readFile ./shared/config/nvim/init.lua;
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

  home.activation.migrateNvimConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    nvim_config="$HOME/.config/nvim"
    if [ -L "$nvim_config" ]; then
      case "$(readlink "$nvim_config")" in
        /nix/store/*-home-manager-files/.config/nvim) rm -f "$nvim_config" ;;
      esac
    fi
  '';

  home.activation.fixCodexRuntime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -L "$HOME/.codex/dotfiles.config.toml" ] && [ ! -e "$HOME/.codex/dotfiles.config.toml" ]; then
      rm -f "$HOME/.codex/dotfiles.config.toml"
    fi

    terminfo_source="/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty"
    terminfo_target="$HOME/.local/share/terminfo/78/xterm-ghostty"
    if [ -f "$terminfo_source" ]; then
      mkdir -p "$(dirname "$terminfo_target")"
      cp "$terminfo_source" "$terminfo_target"
    fi
  '';

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

      "${pkgs.python3}/bin/python3" "${../scripts/seed_merge}/codex.py" "$target" "$source" "$apply_seed" || echo "Warning: failed to sync Codex config seed" >&2
    fi

    if [ "$replace" = true ]; then
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      cp "$source" "$target"
      chmod u+w "$target"
    fi
  '';

  home.activation.seedPiConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for name in settings.json mcp.json; do
      target="$HOME/.pi/agent/$name"
      source="${./shared/ai/pi}/$name"
      repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/ai/pi/$name"
      apply_seed=

      mkdir -p "$(dirname "$target")"
      if [ -f "$target" ] && [ ! -L "$target" ]; then
        if [ -w "$repo_seed" ]; then
          apply_seed="$repo_seed"
        fi
        "${pkgs.python3}/bin/python3" "${../scripts/seed_merge}/pi.py" "$target" "$source" "$apply_seed" || echo "Warning: failed to sync Pi $name seed" >&2
        merge_source="''${apply_seed:-$source}"
        merged="$(mktemp)"
        "${pkgs.jq}/bin/jq" -s '.[0] * .[1]' "$target" "$merge_source" > "$merged"
        mv "$merged" "$target"
      else
        rm -f "$target"
        cp "$source" "$target"
      fi
      chmod u+w "$target"
    done
  '';

  home.activation.seedLazyVimConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/nvim/lazyvim.json"
    source="${./shared/config/nvim/lazyvim.json}"
    repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/config/nvim/lazyvim.json"
    apply_seed=
    base="$HOME/.local/state/dotfiles/lazyvim-seed.json"

    mkdir -p "$(dirname "$target")"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      if [ -w "$repo_seed" ]; then
        apply_seed="$repo_seed"
      fi
      if "${psCommand}" -A -o comm= | "${pkgs.gnugrep}/bin/grep" -Eq '(^|/)nvim$'; then
        echo "Warning: Skipping LazyVim config sync while Neovim is running" >&2
      else
        "${pkgs.python3}/bin/python3" "${../scripts/seed_merge}/lazyvim.py" "$target" "$source" "$apply_seed" "$base" || echo "Warning: failed to sync LazyVim config seed" >&2
      fi
    else
      rm -f "$target"
      cp "$source" "$target"
      mkdir -p "$(dirname "$base")"
      cp "$source" "$base"
    fi
    chmod u+w "$target"
  '';

  xdg.configFile."nvim/init.lua".force = true;
  xdg.configFile."nvim/lua" = forceSource ./shared/config/nvim/lua;
  xdg.configFile."nvim/.gitignore" = forceSource ./shared/config/nvim/.gitignore;
  xdg.configFile."nvim/stylua.toml" = forceSource ./shared/config/nvim/stylua.toml;

  xdg.configFile."fcitx5" = linuxConfig ./unix/config/fcitx5;

  xdg.configFile."uwsm/env-hyprland" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      export XCURSOR_SIZE=48
      export HYPRCURSOR_SIZE=48
      export QT_IM_MODULE=fcitx
      export XMODIFIERS=@im=fcitx
    '';
  };

  xdg.configFile."ghostty/config" = forceSource ./unix/config/ghostty/config;

  xdg.configFile."hypr" = linuxConfig ./unix/config/hypr;

  xdg.configFile."waybar" = linuxConfig ./unix/config/waybar;

}
