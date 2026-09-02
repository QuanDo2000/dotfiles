args@{ config, pkgs, lib, osConfig ? null, ... }:

let
  desktop = args.desktop or false;
  personalApps = args.personalApps or false;
  obsidianSync = args.obsidianSync or false;
  googleDriveSync = args.googleDriveSync or false;
  storageOffsiteBackup = args.storageOffsiteBackup or false;
  systemCompiler = args.systemCompiler or false;
  systemFontconfig = args.systemFontconfig or false;
  systemOpenSSH = args.systemOpenSSH or false;
  machine = import ./host.nix;
  nixosSystem = pkgs.stdenv.hostPlatform.isLinux && osConfig != null;
  standaloneLinux = pkgs.stdenv.hostPlatform.isLinux && !nixosSystem;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
  forceSource = source: {
    inherit source;
    force = true;
  };
  linuxConfig = source: lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) (forceSource source);
  networkServiceHardening = {
    UMask = "0077";
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
  };
  piExtensionsPins = builtins.fromJSON (builtins.readFile ../packages/pi-extensions-release.json);
  piExtensionsReleaseId = piExtensionsPins.releaseId;
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
    "templates.json"
  ];
  obsidianFiles = lib.genAttrs
    (map (name: "Documents/Sync/.obsidian/${name}") obsidianSettings)
    (path: forceSource (./shared/obsidian + "/${lib.removePrefix "Documents/Sync/.obsidian/" path}"));
  obsidianSyncScript = pkgs.writeShellScript "obsidian-sync" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.obsidian-headless pkgs.nodejs ]}:$PATH"

    if ! command -v ob >/dev/null 2>&1; then
      echo "ob not found; run dotfile update to install obsidian-headless" >&2
      exit 0
    fi

    shopt -s nullglob
    for vault in "$HOME"/Documents/*; do
      [ -d "$vault/.obsidian" ] || continue
      if ob sync-status --path "$vault" >/dev/null 2>&1; then
        exec ob sync --path "$vault" --continuous
      fi
    done

    echo "No configured Obsidian vault found under $HOME/Documents" >&2
    exit 0
  '';
  guardedHomeManager = pkgs.writeShellScriptBin "home-manager" ''
    markers=(
      "$HOME/.local/state/dotfiles/google-drive-bisync-initialized"
      "$HOME/.local/state/dotfiles/google-drive-storage-sync-initialized"
      "$HOME/.local/state/dotfiles/storage-offsite-backup-initialized"
    )
    initialized=false
    for marker in "''${markers[@]}"; do
      [ -e "$marker" ] && initialized=true
    done
    if [ "''${1:-}" = switch ] && [ "$initialized" = true ]; then
      correct_profile=false
      for arg in "$@"; do
        case "$arg" in
          *"#${machine.username}@arch-server") correct_profile=true ;;
        esac
      done
      if [ "$correct_profile" != true ]; then
        echo "Refusing Home Manager switch: this host requires ${machine.username}@arch-server." >&2
        exit 1
      fi
    fi
    exec "${config.programs.home-manager.package}/bin/home-manager" "$@"
  '';
  devTerminalPackages = with pkgs; [
    bash-language-server
    codex
    jq
    nil
    nixfmt
    nodejs
    pkgs.pi-agent
    shellcheck
    statix
  ] ++ lib.optionals (pkgs.stdenv.hostPlatform.isLinux && !systemCompiler) [
    gcc
  ];
  standaloneLinuxPackages = with pkgs; lib.optionals (!systemOpenSSH) [ openssh ]
    ++ lib.optionals (!systemFontconfig) [ fontconfig ];
  desktopPackages = with pkgs; [
    grim
    rbw
    slurp
    wl-clipboard
    hyprshutdown
    ghostty
    google-chrome
    pavucontrol
    playerctl
  ];
  personalPackages = with pkgs; [ ankiWithAddons obsidian webcord ];
  obsidianSyncPackages = with pkgs; [ obsidian-headless ];
  profileFile = {
    text = lib.concatStringsSep "\n" [
      "desktop=${lib.boolToString desktop}"
      "personalApps=${lib.boolToString personalApps}"
      "obsidianSync=${lib.boolToString obsidianSync}"
      "googleDriveSync=${lib.boolToString googleDriveSync}"
      "storageOffsiteBackup=${lib.boolToString storageOffsiteBackup}"
      ""
    ];
    force = true;
  };
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
  ++ lib.optionals standaloneLinux [ (lib.hiPrio guardedHomeManager) ]
  ++ lib.optionals (desktop && pkgs.stdenv.hostPlatform.isLinux) desktopPackages
  ++ lib.optionals (personalApps && pkgs.stdenv.hostPlatform.isLinux) personalPackages
  ++ lib.optionals (obsidianSync && pkgs.stdenv.hostPlatform.isLinux) obsidianSyncPackages
  ++ lib.optionals storageOffsiteBackup [ pkgs.restic ];

  home.file = (lib.optionalAttrs (personalApps && pkgs.stdenv.hostPlatform.isLinux) obsidianFiles) // {
    ".config/dotfiles/profile" = profileFile;
    "${homeDir}/.config/jj/config.toml".force = true;
    ".ssh/config" = forceSource ./shared/.ssh/config;
    ".codex/AGENTS.md" = forceSource ./shared/ai/AGENTS.md;
    ".pi/agent/AGENTS.md" = forceSource ./shared/ai/AGENTS.md;
    ".hermes/SOUL.md" = forceSource ./shared/ai/SOUL.md;
    ".agents/skills/systematic-debugging" = forceSource ./shared/ai/skills/systematic-debugging;
    ".agents/skills/test-driven-development" = forceSource ./shared/ai/skills/test-driven-development;
    ".agents/skills/skill-retrospective" = forceSource ./shared/ai/skills/skill-retrospective;
    ".pi/agent/extensions/codex-status.js" = forceSource ./shared/ai/pi/codex-status.js;
    ".pi/agent/extensions/gpg-signing-display" = forceSource ./shared/ai/pi/gpg-signing-display;
    ".pi/agent/extensions/autoresearch" = forceSource ./shared/ai/pi/autoresearch;
    ".pi/agent/extensions/fast-mode" = forceSource ./shared/ai/pi/fast-mode;
    ".pi/agent/locked-extensions/releases/${piExtensionsReleaseId}" = forceSource pkgs.pi-extensions;
    ".local/bin/dotfile" = {
      text = ''
        #!/usr/bin/env bash
        dotfiles_dir="''${DOTFILES_DIR:-$HOME/dotfiles}"
        exec "$dotfiles_dir/dotfile" "$@"
      '';
      executable = true;
      force = true;
    };

    ".local/bin/bitwarden-picker" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) (forceSource ./unix/bin/bitwarden-picker // {
      executable = true;
    });
    ".local/bin/input-method-status" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) (forceSource ../scripts/input-method-status.sh // {
      executable = true;
    });
    ".local/bin/hyprsunset-status" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) (forceSource ../scripts/hyprsunset-status.sh // {
      executable = true;
    });
    ".local/bin/show-keybinds" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) (forceSource ../scripts/show-keybinds.sh // {
      executable = true;
    });
    ".local/bin/restic-recover" = lib.mkIf storageOffsiteBackup (forceSource ./arch-server/restic-recover // {
      executable = true;
    });
    ".local/bin/caf" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (forceSource ./mac/bin/caf // {
      executable = true;
    });
  };

  programs.home-manager.enable = true;

  xdg.configFile."restic/storage-offsite-excludes" = lib.mkIf storageOffsiteBackup {
    text = ''
      **/._*
      **/.DS_Store
      **/*.iso
      **/*.pfx
      **/recovery/**
    '';
  };

  gtk = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    enable = true;
    gtk3.extraConfig.gtk-tooltip-timeout = 200;
  };

  xdg.configFile."mimeapps.list" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    force = true;
  };
  xdg.dataFile."applications/mimeapps.list" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    force = true;
  };

  xdg.mimeApps = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
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

  xdg.userDirs = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
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

  programs.fuzzel = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
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
    enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
    systemd.enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
  };

  programs.hyprlock.enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
  services.hypridle.enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
  services.hyprpolkitagent.enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
  systemd.user.services.hyprpolkitagent = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
  };

  services.hyprsunset.enable = desktop && pkgs.stdenv.hostPlatform.isLinux;
  systemd.user.services.hyprsunset = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    Unit.X-Restart-Triggers = [ "${./unix/config/hypr/hyprsunset.conf}" ];
  };

  services.wl-clip-persist = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    enable = true;
    clipboardType = "regular";
  };
  systemd.user.services.wl-clip-persist = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
  };

  services.mako = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
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
  programs.rclone.enable = googleDriveSync || storageOffsiteBackup;

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
    extraConfig = builtins.readFile ./unix/.tmux.conf;
  };

  systemd.user.services.google-drive-mount = lib.mkIf (googleDriveSync && pkgs.stdenv.hostPlatform.isLinux) {
    Unit = {
      Description = "Google Drive mount";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = "%h/.config/rclone/rclone.conf";
    };

    Service = {
      # fusermount3 needs its setuid wrapper; systemd seccomp restrictions block setuid helpers.
      NoNewPrivileges = false;
      Type = "notify";
      UMask = "0077";
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 700 ${homeDir}/GoogleDrive";
      ExecStart = "${pkgs.rclone}/bin/rclone mount gdrive: ${homeDir}/GoogleDrive --vfs-cache-mode full --cache-dir %h/.cache/rclone --dir-cache-time 1h --poll-interval 15s --file-perms 0600 --dir-perms 0700";
      Restart = "on-failure";
      RestartSec = 10;
    };

    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.google-drive-bisync = lib.mkIf (googleDriveSync && pkgs.stdenv.hostPlatform.isLinux) {
    Unit = {
      Description = "Google Drive two-way sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "%h/.config/rclone/rclone.conf"
        "%h/.local/state/dotfiles/google-drive-bisync-initialized"
      ];
    };

    Service = networkServiceHardening // {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 700 ${homeDir}/Documents/Drive ${homeDir}/Documents/.Drive-backup";
      # debt: one lock serializes jobs that touch the same Drive tree; split only when independent trees need concurrent sync.
      ExecStart = "${pkgs.util-linux}/bin/flock --no-fork --wait 1800 %t/google-drive-sync.lock ${pkgs.rclone}/bin/rclone bisync ${homeDir}/Documents/Drive gdrive:Drive --check-access --check-filename .rclone-bisync-check --create-empty-src-dirs --resilient --recover --max-lock 2m --conflict-resolve newer --max-delete 25 --backup-dir1 ${homeDir}/Documents/.Drive-backup --backup-dir2 gdrive:.Drive-backup --verbose";
      ExecStopPost = "${pkgs.coreutils}/bin/chmod -R u=rwX,go= ${homeDir}/Documents/Drive ${homeDir}/Documents/.Drive-backup";
      KillSignal = "SIGINT";
      TimeoutStartSec = "65m";
      TimeoutStopSec = 120;
    };
  };

  systemd.user.timers.google-drive-bisync = lib.mkIf (googleDriveSync && pkgs.stdenv.hostPlatform.isLinux) {
    Unit.Description = "Sync Google Drive every five minutes";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
      Unit = "google-drive-bisync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.google-drive-storage-sync = lib.mkIf (storageOffsiteBackup && pkgs.stdenv.hostPlatform.isLinux) {
    Unit = {
      Description = "Sync matching Google Drive and Storage folders";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "%h/.config/rclone/rclone.conf"
        "%h/.local/state/dotfiles/google-drive-storage-sync-initialized"
      ];
      ConditionPathIsMountPoint = "/mnt/storage";
    };
    Service = networkServiceHardening // {
      Type = "oneshot";
      Environment = "RCLONE=${pkgs.rclone}/bin/rclone";
      ExecStart = "${pkgs.util-linux}/bin/flock --no-fork --wait 1800 %t/google-drive-sync.lock ${pkgs.python3}/bin/python ${../scripts/google-drive-storage-sync.py}";
      TimeoutStartSec = "infinity";
    };
  };

  systemd.user.timers.google-drive-storage-sync = lib.mkIf (storageOffsiteBackup && pkgs.stdenv.hostPlatform.isLinux) {
    Unit.Description = "Sync matching Google Drive and Storage folders daily";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "google-drive-storage-sync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.storage-offsite-backup = lib.mkIf storageOffsiteBackup {
    Unit = {
      Description = "Back up irreplaceable Storage data to Google Drive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "%h/.config/rclone/rclone.conf"
        "%h/.config/restic/storage-backup-password"
        "%h/.local/state/dotfiles/storage-offsite-backup-initialized"
      ];
      ConditionPathIsMountPoint = "/mnt/storage";
      ConditionPathIsDirectory = [
        "/mnt/storage/Storage/Documents"
        "/mnt/storage/Storage/Book"
        "/mnt/storage/Storage/Music"
      ];
    };
    Service = networkServiceHardening // {
      Type = "oneshot";
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.rclone pkgs.coreutils ]}"
        "RESTIC_REPOSITORY=rclone:gdrive:ServerBackup/restic"
        "RESTIC_PASSWORD_FILE=${homeDir}/.config/restic/storage-backup-password"
        "RESTIC_CACHE_DIR=${homeDir}/.cache/restic"
      ];
      # debt: one lock serializes backup and maintenance; split only if maintenance blocks required backup throughput.
      ExecStart = "${pkgs.util-linux}/bin/flock --no-fork %t/storage-offsite-backup.lock ${pkgs.restic}/bin/restic backup --tag storage-offsite --exclude-caches --iexclude-file=${homeDir}/.config/restic/storage-offsite-excludes /mnt/storage/Storage/Documents /mnt/storage/Storage/Book /mnt/storage/Storage/Music";
      TimeoutStartSec = "infinity";
    };
  };

  systemd.user.timers.storage-offsite-backup = lib.mkIf storageOffsiteBackup {
    Unit.Description = "Back up irreplaceable Storage data daily";
    Timer = {
      OnCalendar = "*-*-* 06:00:00";
      Persistent = true;
      Unit = "storage-offsite-backup.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.storage-offsite-maintenance = lib.mkIf storageOffsiteBackup {
    Unit = {
      Description = "Prune and check the off-site restic repository";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = [
        "%h/.config/rclone/rclone.conf"
        "%h/.config/restic/storage-backup-password"
        "%h/.local/state/dotfiles/storage-offsite-backup-initialized"
      ];
    };
    Service = networkServiceHardening // {
      Type = "oneshot";
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.rclone pkgs.coreutils ]}"
        "RESTIC_REPOSITORY=rclone:gdrive:ServerBackup/restic"
        "RESTIC_PASSWORD_FILE=${homeDir}/.config/restic/storage-backup-password"
        "RESTIC_CACHE_DIR=${homeDir}/.cache/restic"
      ];
      ExecStart = [
        "${pkgs.util-linux}/bin/flock --no-fork %t/storage-offsite-backup.lock ${pkgs.restic}/bin/restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune"
        "${pkgs.util-linux}/bin/flock --no-fork %t/storage-offsite-backup.lock ${pkgs.restic}/bin/restic check --read-data-subset=5%"
      ];
      TimeoutStartSec = "infinity";
    };
  };

  systemd.user.timers.storage-offsite-maintenance = lib.mkIf storageOffsiteBackup {
    Unit.Description = "Maintain the off-site restic repository monthly";
    Timer = {
      OnCalendar = "*-*-08 07:00:00";
      Persistent = true;
      Unit = "storage-offsite-maintenance.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.obsidian-sync = lib.mkIf (obsidianSync && pkgs.stdenv.hostPlatform.isLinux) {
    Unit = {
      Description = "Obsidian Sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = networkServiceHardening // {
      Type = "simple";
      ExecStart = "${obsidianSyncScript}";
      Restart = "on-failure";
      RestartSec = 10;
    };

    Install.WantedBy = [ "default.target" ];
  };

  home.activation.guardStorageOffsiteProfile = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !googleDriveSync && !storageOffsiteBackup)
    (lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      markers=(
        "$HOME/.local/state/dotfiles/google-drive-bisync-initialized"
        "$HOME/.local/state/dotfiles/google-drive-storage-sync-initialized"
        "$HOME/.local/state/dotfiles/storage-offsite-backup-initialized"
      )
      for marker in "''${markers[@]}"; do
        if [ -e "$marker" ]; then
          echo "Refusing generic Home Manager profile: this host is initialized for Google Drive or storage services; use ${machine.username}@arch-server." >&2
          exit 1
        fi
      done
    '');

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
    for spec in settings.json keybindings.json web-search.json:../web-search.json mcp.json; do
      name="''${spec%%:*}"
      relative="''${spec#*:}"
      if [ "$relative" = "$spec" ]; then
        relative="$name"
      fi
      target="$HOME/.pi/agent/$relative"
      source="${./shared/ai/pi}/$name"
      repo_seed="''${DOTFILES_DIR:-$HOME/dotfiles}/config/shared/ai/pi/$name"
      apply_seed=
      base="$HOME/.local/state/dotfiles/pi/$name"

      mkdir -p "$(dirname "$target")"
      if [ -f "$target" ] && [ ! -L "$target" ]; then
        if [ -w "$repo_seed" ]; then
          apply_seed="$repo_seed"
        fi
        "${pkgs.python3}/bin/python3" "${../scripts/seed_merge}/pi.py" "$target" "$source" "$apply_seed" "$base" || echo "Warning: failed to sync Pi $name seed" >&2
      else
        rm -f "$target"
        cp "$source" "$target"
        mkdir -p "$(dirname "$base")"
        cp "$source" "$base"
      fi
      chmod u+w "$target"
    done

    rm -f "$HOME/.pi/agent/extensions/subagent/config.json"
    rmdir "$HOME/.pi/agent/extensions/subagent" 2>/dev/null || true
    rm -f "$HOME/.local/state/dotfiles/pi/subagent-config.json"
    rm -f "$HOME/.pi/agent/pi-lsp.json" "$HOME/.local/state/dotfiles/pi/pi-lsp.json"
  '';

  home.activation.seedLazyLock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    managed_file_current() {
      [ -f "$2" ] && [ ! -L "$2" ] &&
        [ "$("${pkgs.coreutils}/bin/stat" -c %a "$2")" = 600 ] &&
        "${pkgs.diffutils}/bin/cmp" -s "$1" "$2"
    }

    target="$HOME/.config/nvim/lazy-lock.json"
    if ! managed_file_current "${./shared/config/nvim/lazy-lock.json}" "$target"; then
      mkdir -p "$(dirname "$target")"
      tmp="$(mktemp "$target.tmp.XXXXXX")"
      cp "${./shared/config/nvim/lazy-lock.json}" "$tmp"
      chmod 600 "$tmp"
      mv "$tmp" "$target"
    fi
  '';

  xdg.configFile."nvim/init.lua".force = true;
  xdg.configFile."nvim/lua" = forceSource ./shared/config/nvim/lua;
  xdg.configFile."nvim/mason-tools.json" = forceSource ./shared/config/nvim/mason-tools.json;
  xdg.configFile."nvim/.gitignore" = forceSource ./shared/config/nvim/.gitignore;
  xdg.configFile."nvim/stylua.toml" = forceSource ./shared/config/nvim/stylua.toml;

  xdg.configFile."fcitx5" = linuxConfig ./unix/config/fcitx5;

  xdg.configFile."uwsm/env-hyprland" = lib.mkIf (desktop && pkgs.stdenv.hostPlatform.isLinux) {
    text = ''
      export XCURSOR_SIZE=48
      export HYPRCURSOR_SIZE=48
      export QT_IM_MODULE=fcitx
      export XMODIFIERS=@im=fcitx
    '';
  };

  xdg.configFile."ghostty/config" = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin || (desktop && pkgs.stdenv.hostPlatform.isLinux)) (forceSource ./unix/config/ghostty/config);

  xdg.configFile."hypr" = linuxConfig ./unix/config/hypr;

  xdg.configFile."waybar" = linuxConfig ./unix/config/waybar;

}
