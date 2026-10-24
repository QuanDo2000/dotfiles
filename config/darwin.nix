{ pkgs, ... }:

let
  machine = import ./host.nix;
in
{
  system.stateVersion = 6;
  system.primaryUser = machine.username;

  nixpkgs.config.allowUnfreePredicate = package: pkgs.lib.getName package == "rex";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Download the security-overridden Node builds published by macOS CI.
    extra-substituters = [ "https://quando-dotfiles.cachix.org" ];
    extra-trusted-public-keys = [
      "quando-dotfiles.cachix.org-1:i6zSDlDRojslWeg2UgGcS25jpOs/km8ctjWABaN1h3Y="
    ];
  };

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    # Preserve Touch ID in detached terminal sessions, including Rex.
    reattach = true;
  };

  users.users.${machine.username} = {
    home = "/Users/${machine.username}";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # Rex's native macOS appearance preferences; init.lua only defines bindings.
  system.defaults.CustomUserPreferences."com.superlogical.rex" = {
    "Workspace.terminalFontName" = "FiraCode Nerd Font";
    "Workspace.terminalFallbackFontNames" = [
      "Noto Sans"
      "Noto Sans CJK SC"
      "Noto Sans Symbols"
      "Symbols Nerd Font"
      "Noto Color Emoji"
    ];
    # The signed app bundle is immutable; dotfile update owns its version.
    SUEnableAutomaticChecks = false;
    SUAutomaticallyUpdate = false;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.users.${machine.username} = import ./home.nix;
}
