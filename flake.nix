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

  outputs = { nixpkgs, home-manager, nix-darwin, ... }: {
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

    homeConfigurations."quando@arch" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [ ./config/home.nix ];
    };
  };
}
