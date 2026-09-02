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
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nix-darwin, nixos-wsl, ... }:
    let
      machine = import ./config/host.nix;
      overlays = [
        (final: _prev: {
          codex = final.callPackage ./packages/codex-release.nix { };
          obsidian-headless = final.callPackage ./packages/obsidian-headless.nix { };
          pi-agent = final.callPackage ./packages/pi-agent.nix { };
          pi-extensions = final.callPackage ./packages/pi-extensions.nix { };
          webcord = final.callPackage ./packages/webcord-release.nix { };
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
      devShell = pkgs: pkgs.mkShell {
        LAZY_NVIM_PATH = "${pkgs.vimPlugins.lazy-nvim}";
        packages = with pkgs; [
          git
          jq
          jujutsu
          neovim
          nodejs
          pi-agent
          python3
          shellcheck
          tree-sitter
          tmux
          zsh
        ];
      };
      ciShell = pkgs: pkgs.mkShellNoCC {
        LAZY_NVIM_PATH = "${pkgs.vimPlugins.lazy-nvim}";
        packages = with pkgs; [
          git
          jq
          jujutsu
          neovim
          python3
          tree-sitter
          tmux
        ];
      };
    in
    {
      packages.x86_64-linux.codex = linuxPkgs.codex;
      packages.x86_64-linux.obsidian-headless = linuxPkgs.obsidian-headless;
      packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent;
      packages.x86_64-linux.pi-extensions = linuxPkgs.pi-extensions;
      packages.x86_64-linux.prefetch-npm-deps = linuxPkgs.prefetch-npm-deps;
      packages.aarch64-darwin.codex = darwinPkgs.codex;
      packages.aarch64-darwin.pi-extensions = darwinPkgs.pi-extensions;
      packages.aarch64-darwin.prefetch-npm-deps = darwinPkgs.prefetch-npm-deps;

      nixosConfigurations."${machine.hostName}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = overlays; }
          ./config/nixos/configuration.nix
          home-manager.nixosModules.home-manager
        ];
      };

      nixosConfigurations."${machine.hostName}-wsl" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = overlays; }
          nixos-wsl.nixosModules.default
          ./config/nixos-wsl/configuration.nix
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

      homeConfigurations."${machine.username}@arch-server" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = {
          obsidianSync = true;
          googleDriveSync = true;
          storageOffsiteBackup = true;
          systemCompiler = true;
        };
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

      devShells.x86_64-linux.default = devShell linuxPkgs;
      devShells.x86_64-linux.ci = ciShell linuxPkgs;
      devShells.aarch64-darwin.default = devShell darwinPkgs;
      devShells.aarch64-darwin.ci = ciShell darwinPkgs;
    };
}
