assert(vim.g.raw_neovim == true, "raw Neovim marker missing")
assert(vim.g.mapleader == " ")
assert(vim.o.number and vim.o.relativenumber and vim.o.undofile)
assert(vim.o.clipboard == "unnamedplus")
assert(vim.o.splitbelow and vim.o.splitright and not vim.o.wrap)

local windows = vim.fn.has("win32") == 1
local expected = {
  [" ff"] = windows and "Find Files" or "Find Files (FFF)",
  [" sg"] = windows and "Grep" or "Grep (FFF)",
  [" fe"] = "Explorer (Root Dir)",
  [" aa"] = "Toggle Pi",
  [" af"] = "Send File",
  [" at"] = "Send Position",
  [" qs"] = "Restore Session",
  [" cf"] = "Format",
}
local maps = {}
for _, map in ipairs(vim.api.nvim_get_keymap("n")) do maps[map.lhs] = map.desc end
for lhs, desc in pairs(expected) do assert(maps[lhs] == desc, lhs .. " mapping missing") end
assert(vim.fn.maparg("jk", "i") ~= "", "jk mapping missing")
assert(maps[" e"] == "Explorer (Root Dir)" and maps[" E"] == "Explorer (cwd)", "explorer aliases missing")

local lazy = require("lazy.core.config")
assert(not lazy.plugins.LazyVim, "LazyVim must not be loaded")
for _, plugin in ipairs({
  "blink.cmp",
  "catppuccin",
  "conform.nvim",
  "gitsigns.nvim",
  "mason.nvim",
  "mini.hipatterns",
  "mini.surround",
  "nvim-lint",
  "nvim-lspconfig",
  "nvim-treesitter",
  "persistence.nvim",
  "render-markdown.nvim",
  "snacks.nvim",
  "yanky.nvim",
}) do
  assert(lazy.plugins[plugin], plugin .. " missing")
end
assert((not windows) == (lazy.plugins["fff.nvim"] and lazy.plugins["fff.nvim"].enabled ~= false), "fff.nvim platform gate is wrong")
require("lazy").load({ plugins = { "conform.nvim" } })
local format_on_save = false
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "BufWritePre" })) do
  if autocmd.desc == "Format on save" then format_on_save = true end
end
assert(format_on_save, "format-on-save autocmd missing")
print("RAW_CONFIG_OK")
