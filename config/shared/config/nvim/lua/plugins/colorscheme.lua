return {
  -- catppuccin options; lazy.nvim runs require("catppuccin").setup(opts).
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "macchiato",
      compile = true,
    },
  },
  -- LazyVim applies the colorscheme (single source of truth).
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
