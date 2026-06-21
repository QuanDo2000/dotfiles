return {
  -- catppuccin options; lazy.nvim runs require("catppuccin").setup(opts).
  -- Pin background.dark to macchiato: catppuccin re-resolves its flavour from the
  -- `background` map whenever vim.o.background is set (LazyVim sets it on startup),
  -- and the default background.dark="mocha" silently overrides `flavour`. Combined
  -- with the explicit colorscheme name below, this keeps nvim on macchiato instead
  -- of rendering washed-out mocha against the macchiato terminal theme.
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "macchiato",
      background = { light = "latte", dark = "macchiato" },
    },
  },
  -- LazyVim applies the colorscheme. Use the explicit per-flavour name
  -- (catppuccin-macchiato) rather than "catppuccin": the bare name goes through
  -- catppuccin's auto/background flavour resolution, which lands on mocha here.
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-macchiato",
    },
  },
}
