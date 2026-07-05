{ ... }:

{
  system.stateVersion = 6;

  users.users.quando.home = "/Users/quando";

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "before-home-manager";
  home-manager.users.quando = import ./home.nix;
}
