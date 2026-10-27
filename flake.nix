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
    # Immutable upstream storage URL resolved after authenticating to the Rex
    # package host. No credentials are needed during evaluation or CI.
    rex-linux = {
      url = "https://wthziax2yejsqc4k.public.blob.vercel-storage.com/public/pkgs/rex/nix/snapshot/0.0.1793075605-gf47cf6.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nix-darwin, nixos-wsl, rex-linux, ... }:
    let
      machine = import ./config/host.nix;
      overlays = [
        (import ./packages/emudhra-overlay.nix)
        (final: _prev: {
          obsidian-headless = final.callPackage ./packages/obsidian-headless.nix { };
          hyprsunset-status = final.callPackage ./packages/hyprsunset-status.nix { };
          pi-agent = final.callPackage ./packages/pi-agent.nix { };
          pi-extensions = final.callPackage ./packages/pi-extensions.nix { };
          webcord = final.callPackage ./packages/webcord-release.nix { };
          rex = final.callPackage ./packages/rex.nix { };
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
          (python3.withPackages (packages: [ packages.pyyaml ]))
          rclone
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
      packages.x86_64-linux.obsidian-headless = linuxPkgs.obsidian-headless;
      packages.x86_64-linux.rex = rex-linux.packages.x86_64-linux.rex;
      packages.x86_64-linux.rex-auth-python = linuxPkgs.python3;
      packages.x86_64-linux.nodejs = linuxPkgs.nodejs;
      packages.x86_64-linux.hyprsunset-status = linuxPkgs.hyprsunset-status;
      packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent;
      packages.x86_64-linux.pi-extensions = linuxPkgs.pi-extensions;
      packages.x86_64-linux.prefetch-npm-deps = linuxPkgs.prefetch-npm-deps;
      packages.aarch64-darwin.pi-extensions = darwinPkgs.pi-extensions;
      packages.aarch64-darwin.rex = darwinPkgs.rex;
      packages.aarch64-darwin.nodejs = darwinPkgs.nodejs;
      packages.aarch64-darwin.prefetch-npm-deps = darwinPkgs.prefetch-npm-deps;

      nixosConfigurations."${machine.hostName}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = overlays; }
          ./config/nixos/configuration.nix
          home-manager.nixosModules.home-manager
          { home-manager.sharedModules = [ rex-linux.homeManagerModules.default ./config/rex-linux.nix ]; }
        ];
      };

      nixosConfigurations."${machine.hostName}-wsl" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = overlays; }
          nixos-wsl.nixosModules.default
          ./config/nixos-wsl/configuration.nix
          home-manager.nixosModules.home-manager
          { home-manager.sharedModules = [ rex-linux.homeManagerModules.default ./config/rex-linux.nix ]; }
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
        modules = [ ./config/home.nix rex-linux.homeManagerModules.default ./config/rex-linux.nix ];
      };

      homeConfigurations."${machine.username}@arch-server" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = {
          obsidianSync = true;
          googleDriveSync = true;
          storageOffsiteBackup = true;
          systemCompiler = true;
        };
        modules = [
          ./config/home.nix rex-linux.homeManagerModules.default ./config/rex-linux.nix
          # Arch only: existing tailscaled identifies callers; node owner only.
          { services.rex.extraListen = [ "tailnet://:7297" ]; }
        ];
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
