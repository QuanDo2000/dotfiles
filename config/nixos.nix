{ ... }:

let
  machine = import ./host.nix;
in
{
  imports = [
    ./nixos/configuration.nix
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${machine.username} = import ./home.nix;
}
