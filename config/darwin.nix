{ pkgs, ... }:

let
  machine = import ./host.nix;
in
{
  system.stateVersion = 6;
  system.primaryUser = machine.username;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  users.users.${machine.username} = {
    home = "/Users/${machine.username}";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    bash
    git
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "before-home-manager";
  home-manager.users.${machine.username} = import ./home.nix;
}
