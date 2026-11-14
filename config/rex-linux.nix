{ config, lib, pkgs, ... }:
{
  programs.rex = {
    enable = true;
    # The shared SSH config is owned by dotfiles, not programs.ssh.
    sshGuard = false;
  };
  services.rex.enable = true;

  # Noninteractive SSH shells may omit the Nix profile from PATH. Rex also
  # checks ~/.local/bin when opening a native ssh:// connection.
  home.file.".local/bin/rex".source = "${config.programs.rex.package}/bin/rex";

  home.file.".ssh/config".source = lib.mkForce (pkgs.writeText "ssh-config-with-rex" ''
    Include ${config.programs.rex.package}/share/rex/ssh_config.d/50-rex.conf
    Match all
    ${config.home.file.".ssh/config".text}
  '');
}
