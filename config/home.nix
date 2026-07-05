{ pkgs, lib, ... }:

let
  machine = import ./host.nix;
  homeDir =
    if pkgs.stdenv.isDarwin then "/Users/${machine.username}" else "/home/${machine.username}";
in
{
  home.username = machine.username;
  home.homeDirectory = homeDir;
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    neovim
    tmux
    fzf
    fd
    ripgrep
    lazygit
    zoxide
    gnupg
    nodejs
    jujutsu
    starship
    ast-grep
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    fontconfig
    nerd-fonts.fira-code
    wl-clipboard
    openssh
    lua5_1
    luarocks
    tree-sitter
    unzip
  ]
  ++ lib.optional (pkgs.stdenv.isLinux && pkgs ? codex) pkgs.codex
  ++ lib.optional (pkgs.stdenv.isLinux && pkgs ? codebase-memory-mcp) pkgs.codebase-memory-mcp;

  home.file.".gitconfig" = {
    source = ./shared/.gitconfig;
    force = true;
  };

  home.file.".vimrc" = {
    source = ./shared/.vimrc;
    force = true;
  };

  home.file.".tmux.conf" = {
    source = ./unix/.tmux.conf;
    force = true;
  };

  home.file.".zprofile" = {
    source = ./unix/.zprofile;
    force = true;
  };

  home.file.".zshrc.base" = {
    source = ./unix/.zshrc.base;
    force = true;
  };

  home.file.".ssh/config" = {
    source = ./shared/.ssh/config;
    force = true;
  };

  home.file.".claude/settings.json" = {
    source = ./shared/ai/claude/settings.json;
    force = true;
  };

  home.file.".codex/config.toml" = {
    source = ./shared/ai/codex/config.toml;
    force = true;
  };

  home.file.".tmux/plugins/tmux-yank" = {
    source = "${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank";
    force = true;
  };

  home.file.".tmux/plugins/catppuccin/tmux" = {
    source = "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";
    force = true;
  };

  programs.home-manager.enable = true;

  xdg.configFile."starship.toml" = {
    source = ./shared/config/starship.toml;
    force = true;
  };

  xdg.configFile."jj" = {
    source = ./shared/config/jj;
    force = true;
  };

  xdg.configFile."nvim" = {
    source = ./shared/config/nvim;
    force = true;
  };

  xdg.configFile."fcitx5" = {
    source = ./unix/config/fcitx5;
    force = true;
  };

  xdg.configFile."ghostty/config" = {
    source = ./unix/config/ghostty/config;
    force = true;
  };

  xdg.configFile."hypr" = {
    source = ./unix/config/hypr;
    force = true;
  };

  xdg.configFile."waybar" = {
    source = ./unix/config/waybar;
    force = true;
  };

  xdg.dataFile."zsh/plugins/zsh-autosuggestions" = {
    source = "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";
    force = true;
  };

  xdg.dataFile."zsh/plugins/fast-syntax-highlighting" = {
    source = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";
    force = true;
  };

  xdg.dataFile."zsh/plugins/fzf-tab" = {
    source = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
    force = true;
  };

  home.file.".zshrc.mac" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./mac/.zshrc.mac;
    force = true;
  };

  home.file.".local/bin/caf" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./mac/bin/caf;
    executable = true;
    force = true;
  };
}
