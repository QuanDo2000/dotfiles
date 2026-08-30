# NixOS-WSL system configuration. Hardware, bootloader, and desktop settings
# belong to the physical NixOS configuration in ../nixos/configuration.nix.
{ pkgs, ... }:

let
  machine = import ../host.nix;
in
{
  wsl.enable = true;
  wsl.defaultUser = machine.username;
  wsl.wslConf.interop.appendWindowsPath = false;

  system.stateVersion = machine.stateVersion;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nixpkgs.config.allowUnfree = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  time.timeZone = machine.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  networking.hostName = machine.hostName;

  programs.zsh.enable = true;
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=30
  '';
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
    settings = {
      default-cache-ttl = 28800;
      max-cache-ttl = 86400;
    };
  };

  users.users.${machine.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {
    desktop = false;
    personalApps = false;
    obsidianSync = false;
    googleDriveSync = false;
    storageOffsiteBackup = false;
  };
  home-manager.users.${machine.username} = import ../home.nix;
}
