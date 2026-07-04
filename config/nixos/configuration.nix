# Preliminary NixOS system configuration for these dotfiles.
#
# This is a STARTING TEMPLATE — the `# EDIT:` lines below are per-machine and
# must be tuned on a real box. `dotfile packages` symlinks this file to
# /etc/nixos/configuration.nix and runs `nixos-rebuild switch`.
#
# hardware-configuration.nix is machine-generated (`nixos-generate-config`),
# per-machine, and git-ignored. Generate it once on the target machine.
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- System core ---------------------------------------------------------
  system.stateVersion = "24.11";              # EDIT: match the install's NixOS release
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Asia/Ho_Chi_Minh";         # EDIT: your timezone
  i18n.defaultLocale = "en_US.UTF-8";
  networking.hostName = "nixos";              # EDIT: your hostname
  networking.networkmanager.enable = true;

  # --- Boot ----------------------------------------------------------------
  boot.loader.systemd-boot.enable = true;     # EDIT: use GRUB instead if needed
  boot.loader.efi.canTouchEfiVariables = true;

  # --- User ----------------------------------------------------------------
  programs.zsh.enable = true;
  users.users.quan = {                        # EDIT: your username
    isNormalUser = true;
    description = "Quan Do";                   # EDIT
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
  };

  # --- Desktop: Hyprland + greetd login ------------------------------------
  programs.hyprland.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      user = "greeter";
    };
  };

  # --- Input method: fcitx5 ------------------------------------------------
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-unikey ];   # EDIT: your input addons
  };

  # --- Fonts ---------------------------------------------------------------
  fonts.packages = with pkgs; [ nerd-fonts.fira-code ];

  # --- Packages ------------------------------------------------------------
  # Ported from ARCH_PACKAGES in scripts/packages.sh. App config files stay as
  # symlinked dotfiles (dotfile symlinks); NixOS only installs the binaries.
  environment.systemPackages = with pkgs; [
    git
    zsh
    tmux
    neovim
    fzf
    fd
    ripgrep
    lazygit
    jujutsu
    starship
    zoxide
    gnupg
    wl-clipboard
    openssh
    unzip
    fontconfig
    tree-sitter
    lua5_1
    luarocks
    waybar
    ghostty
    opencode
  ];
}
