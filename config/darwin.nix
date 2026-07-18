{ pkgs, ... }:

let
  machine = import ./host.nix;
in
{
  system.stateVersion = 6;
  system.primaryUser = machine.username;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.${machine.username} = {
    home = "/Users/${machine.username}";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs.storageOffsiteBackup = false;
  home-manager.users.${machine.username} = import ./home.nix;
}
