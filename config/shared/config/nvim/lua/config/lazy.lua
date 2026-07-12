local lazy_ok, lazy = pcall(require, "lazy")
if not lazy_ok then
  vim.api.nvim_echo({
    { "lazy.nvim is missing; run dotfile update\n", "ErrorMsg" },
  }, true, {})
  vim.fn.getchar()
  os.exit(1)
end

lazy.setup({
  spec = {
    -- Home Manager owns lazy.nvim in the read-only Nix store.
    { "folke/lazy.nvim", enabled = false },
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = false,
    notify = false,
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
