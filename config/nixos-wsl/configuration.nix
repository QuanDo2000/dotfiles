# NixOS-WSL system configuration. Hardware, bootloader, and desktop settings
# belong to the physical NixOS configuration in ../nixos/configuration.nix.
{ pkgs, ... }:

let
  machine = import ../host.nix;
in
{
  imports = [ ../nixos/common.nix ];

  wsl.enable = true;
  wsl.defaultUser = machine.username;
  wsl.wslConf.interop.appendWindowsPath = false;

  programs.gnupg.agent.pinentryPackage = pkgs.pinentry-curses;
  users.users.${machine.username}.extraGroups = [ "wheel" ];
}
