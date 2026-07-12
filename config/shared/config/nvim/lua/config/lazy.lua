if vim.fn.has("win32") == 1 then
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=stable",
      "https://github.com/folke/lazy.nvim.git",
      lazypath,
    })
    if vim.v.shell_error ~= 0 then
      error("Failed to clone lazy.nvim")
    end
  end
  vim.opt.rtp:prepend(lazypath)
end

local lazy_ok, lazy = pcall(require, "lazy")
if not lazy_ok then
  vim.api.nvim_echo({
    { "lazy.nvim is missing; run dotfile update\n", "ErrorMsg" },
  }, true, {})
  vim.fn.getchar()
  os.exit(1)
end

local lazy_spec = vim.fn.has("win32") == 1 and { "folke/lazy.nvim" } or { "folke/lazy.nvim", enabled = false }

lazy.setup({
  spec = {
    -- Home Manager owns lazy.nvim on Unix; Lazy manages its Windows clone.
    lazy_spec,
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
