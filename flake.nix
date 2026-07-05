{
  description = "Quan's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nix-darwin, ... }:
    let
      machine = import ./config/host.nix;
      linuxPkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./config/nixos.nix
          home-manager.nixosModules.home-manager
        ];
      };

      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./config/darwin.nix
          home-manager.darwinModules.home-manager
        ];
      };

      homeConfigurations."${machine.username}@arch" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [ ./config/home.nix ];
      };

      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${home-manager.packages.x86_64-linux.home-manager}/bin/home-manager";
      };
    };
}
