# Shared physical NixOS / NixOS-WSL core; platform-specific settings stay in their modules.
{ pkgs, ... }:

let
  machine = import ../host.nix;
in
{
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
    settings = {
      default-cache-ttl = 28800;
      max-cache-ttl = 86400;
    };
  };
  users.users.${machine.username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${machine.username} = import ../home.nix;
}
