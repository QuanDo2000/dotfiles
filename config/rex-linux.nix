{ config, lib, pkgs, ... }:
{
  programs.rex = {
    enable = true;
    # The shared SSH config is owned by dotfiles, not programs.ssh.
    sshGuard = false;
  };
  services.rex.enable = true;

  home.file.".ssh/config".source = lib.mkForce (pkgs.writeText "ssh-config-with-rex" ''
    Include ${config.programs.rex.package}/share/rex/ssh_config.d/50-rex.conf
    Match all
    ${config.home.file.".ssh/config".text}
  '');
}
