{ ... }:

let
  machine = import /etc/nixos/machine.nix;
in
{
  imports = [
    ./nixos/configuration.nix
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "before-home-manager";
  home-manager.users.${machine.username} = import ./home.nix;
}
