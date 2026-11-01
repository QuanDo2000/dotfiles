# One fresh, pure evaluation of the real flake for each profile test run.
{ flakeRef, includePlatformDrvPaths ? false }:
let
  flake = builtins.getFlake flakeRef;
  machine = import (flake.outPath + "/config/host.nix");
  summarize = import ./profile-summary.nix;
  linux = flake.homeConfigurations."${machine.username}@linux".config;
  arch = flake.homeConfigurations."${machine.username}@arch-server".config;
  nixos = flake.nixosConfigurations.${machine.hostName}.config;
  nixosWsl = flake.nixosConfigurations."${machine.hostName}-wsl".config;
  darwin = flake.darwinConfigurations.mac.config;
in
{
  profiles = {
    linux = summarize linux;
    arch-server = summarize arch;
    nixos = summarize nixos.home-manager.users.${machine.username};
    nixos-wsl = summarize nixosWsl.home-manager.users.${machine.username};
    darwin = summarize darwin.home-manager.users.${machine.username};
  };
  nixosWrappers = builtins.attrNames nixos.security.wrappers;
  storageGuard = arch.home.activation.checkStorageOffsiteLocalExcludes;
  homePackageContracts = import ./home-package-contracts.nix { inherit flake machine; };
  packageSources = {
    linux = flake.packages.x86_64-linux.pi-extensions.outPath;
    darwin = flake.packages.aarch64-darwin.pi-extensions.outPath;
  };
}
// (if includePlatformDrvPaths then {
  # Same checked configs as the full summaries, not another HM constructor.
  # Keep Linux-before-Arch failure order and completed-Linux diagnostics.
  platformDrvPaths =
    let
      linuxDrv = linux.home.activationPackage.drvPath;
      archDrv = arch.home.activationPackage.drvPath;
    in builtins.seq linuxDrv (builtins.trace linuxDrv (builtins.seq archDrv {
      inherit (machine) username;
      linux = linuxDrv;
      arch-server = archDrv;
    }));
} else { })
