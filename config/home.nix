{ pkgs, ... }:

{
  home.username = "quando";
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/quando" else "/home/quando";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    git
    home-manager
    starship
  ];

  home.file.".gitconfig" = {
    source = ./shared/.gitconfig;
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
}
