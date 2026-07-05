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

  programs.home-manager.enable = true;

  xdg.configFile."starship.toml" = {
    source = ./shared/config/starship.toml;
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
