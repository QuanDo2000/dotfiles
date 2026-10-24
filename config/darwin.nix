{ pkgs, ... }:

let
  machine = import ./host.nix;
in
{
  system.stateVersion = 6;
  system.primaryUser = machine.username;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Download the security-overridden Node builds published by macOS CI.
    extra-substituters = [ "https://quando-dotfiles.cachix.org" ];
    extra-trusted-public-keys = [
      "quando-dotfiles.cachix.org-1:i6zSDlDRojslWeg2UgGcS25jpOs/km8ctjWABaN1h3Y="
    ];
  };

  users.users.${machine.username} = {
    home = "/Users/${machine.username}";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.users.${machine.username} = import ./home.nix;
}
