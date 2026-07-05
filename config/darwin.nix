{ pkgs, ... }:

{
  system.stateVersion = 6;
  system.primaryUser = "quando";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  users.users.quando.home = "/Users/quando";
  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    bash
    tmux
    git
    neovim
    fzf
    fd
    ripgrep
    gnupg
    lazygit
    ast-grep
    zoxide
    jujutsu
    starship
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "before-home-manager";
  home-manager.users.quando = import ./home.nix;
}
