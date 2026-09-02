config:
let
  packageName = package:
    if package ? pname then package.pname
    else (builtins.parseDrvName package.name).name;
  wantedBy = units:
    builtins.mapAttrs (_: unit: unit.Install.WantedBy or [ ]) units;
in
{
  packages = map packageName config.home.packages;
  services = builtins.attrNames config.systemd.user.services;
  timers = builtins.attrNames config.systemd.user.timers;
  files = builtins.attrNames config.home.file;
  marker = config.home.file.".config/dotfiles/profile".text;
  sessionVariables = config.home.sessionVariables;
  serviceWanted = wantedBy config.systemd.user.services;
  timerWanted = wantedBy config.systemd.user.timers;
  xdgFiles = builtins.attrNames config.xdg.configFile;
  fileMeta = builtins.mapAttrs (_: value: {
    force = value.force or false;
    executable = value.executable or false;
    source = if value ? source then builtins.toString value.source else null;
  }) config.home.file;
  activations = builtins.mapAttrs (_: value: value.data or "") config.home.activation;
  mimeDefaults = config.xdg.mimeApps.defaultApplications or {};
  userDirs = {
    enable = config.xdg.userDirs.enable or false;
    documents = config.xdg.userDirs.documents or null;
    download = config.xdg.userDirs.download or null;
    desktop = config.xdg.userDirs.desktop or null;
  };
  programs = {
    rclone = config.programs.rclone.enable or false;
    fuzzel = config.programs.fuzzel.enable or false;
    fuzzelSettings = config.programs.fuzzel.settings or {};
    waybar = config.programs.waybar.enable or false;
    waybarSystemd = config.programs.waybar.systemd.enable or false;
    wlClipPersist = config.services.wl-clip-persist.enable or false;
    wlClipPersistType = config.services.wl-clip-persist.clipboardType or null;
    mako = config.services.mako.enable or false;
    makoSettings = config.services.mako.settings or {};
    hyprpolkitagent = config.services.hyprpolkitagent.enable or false;
    hyprsunset = config.services.hyprsunset.enable or false;
    tmuxPlugins = map (plugin: plugin.plugin.pname or plugin.plugin.name or "") config.programs.tmux.plugins;
  };
  systemdUserEnable = config.systemd.user.enable or false;
  serviceAttrs = builtins.mapAttrs (_: service: {
    description = service.Unit.Description or "";
    after = service.Unit.After or [];
    wants = service.Unit.Wants or [];
    conditionPaths = service.Unit.ConditionPathExists or [];
    conditionMount = service.Unit.ConditionPathIsMountPoint or null;
    conditionDirectories = service.Unit.ConditionPathIsDirectory or [];
    umask = service.Service.UMask or null;
    noNewPrivileges = service.Service.NoNewPrivileges or false;
    restrictSUIDSGID = service.Service.RestrictSUIDSGID or false;
    restrictRealtime = service.Service.RestrictRealtime or false;
    lockPersonality = service.Service.LockPersonality or false;
    systemCallArchitectures = service.Service.SystemCallArchitectures or null;
    restrictAddressFamilies = service.Service.RestrictAddressFamilies or [];
    execStart = service.Service.ExecStart or [];
    execStartPre = service.Service.ExecStartPre or [];
    execStopPost = service.Service.ExecStopPost or [];
    timeoutStart = service.Service.TimeoutStartSec or null;
    timeoutStop = service.Service.TimeoutStopSec or null;
    environment = service.Service.Environment or [];
  }) config.systemd.user.services;
  timerAttrs = builtins.mapAttrs (_: timer: {
    wantedBy = timer.Install.WantedBy or [];
    calendar = timer.Timer.OnCalendar or null;
    onBoot = timer.Timer.OnBootSec or null;
    onActive = timer.Timer.OnUnitActiveSec or null;
    persistent = timer.Timer.Persistent or false;
  }) config.systemd.user.timers;
}
