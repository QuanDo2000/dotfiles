{ pkgs, ... }:
{
  # Imported only by the Arch server profile. Requires its existing Docker/VPN stack.
  systemd.user.services.qbittorrent-calendar-retention = {
    Unit = {
      Description = "Remove completed torrents after 30 calendar days";
      ConditionPathExists = [ "/usr/bin/docker" "%h/Downloads/Torrent" ];
    };
    Service = {
      Type = "oneshot";
      Environment = "TMPDIR=%t";
      ExecStart = "${pkgs.python3}/bin/python3 ${../scripts/qbittorrent-calendar-retention.py} --apply";
      TimeoutStartSec = "5m";
      NoNewPrivileges = true;
    };
  };
  systemd.user.timers.qbittorrent-calendar-retention = {
    Unit.Description = "Check calendar-age torrent retention hourly";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
      Unit = "qbittorrent-calendar-retention.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
