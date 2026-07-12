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
      overlays = [
        (final: _prev: {
          codex = final.callPackage ./packages/codex-release.nix { };
          fff-mcp = final.callPackage ./packages/fff-mcp.nix { };
          obsidian-headless = final.callPackage ./packages/obsidian-headless.nix { };
          pi-agent = final.callPackage ./packages/pi-agent.nix { };
        })
      ];
      linuxPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        inherit overlays;
      };
      darwinPkgs = import nixpkgs {
        system = "aarch64-darwin";
        config.allowUnfree = true;
        inherit overlays;
      };
    in
    {
      packages.x86_64-linux.codex = linuxPkgs.codex;
      packages.x86_64-linux.fff-mcp = linuxPkgs.fff-mcp;
      packages.x86_64-linux.obsidian-headless = linuxPkgs.obsidian-headless;
      packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent;
      packages.aarch64-darwin.codex = darwinPkgs.codex;
      packages.aarch64-darwin.fff-mcp = darwinPkgs.fff-mcp;

      nixosConfigurations."${machine.hostName}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = overlays; }
          ./config/nixos/configuration.nix
          home-manager.nixosModules.home-manager
        ];
      };

      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          { nixpkgs.overlays = overlays; }
          ./config/darwin.nix
          home-manager.darwinModules.home-manager
        ];
      };

      homeConfigurations."${machine.username}@linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [ ./config/home.nix ];
      };

      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${home-manager.packages.x86_64-linux.home-manager}/bin/home-manager";
      };

      apps.aarch64-darwin.darwin-rebuild = {
        type = "app";
        program = "${nix-darwin.packages.aarch64-darwin.darwin-rebuild}/bin/darwin-rebuild";
      };

      devShells.x86_64-linux.default = linuxPkgs.mkShell {
        packages = with linuxPkgs; [
          git
          gh
          powershell
          shellcheck
        ];
      };
    };
}
