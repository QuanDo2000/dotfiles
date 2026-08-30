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
  serviceWanted = wantedBy config.systemd.user.services;
  timerWanted = wantedBy config.systemd.user.timers;
  xdgFiles = builtins.attrNames config.xdg.configFile;
}
