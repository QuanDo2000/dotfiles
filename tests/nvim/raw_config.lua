assert(vim.g.raw_neovim == true, "raw Neovim marker missing")
assert(vim.g.mapleader == " ")
assert(vim.o.number and vim.o.relativenumber and vim.o.undofile)
assert(vim.o.clipboard == "unnamedplus")
assert(vim.o.splitbelow and vim.o.splitright and not vim.o.wrap)
assert(vim.o.autowrite and vim.o.linebreak and vim.o.shiftround and vim.o.smoothscroll)
assert(vim.o.conceallevel == 2 and vim.o.undolevels == 10000 and vim.o.virtualedit == "block")

local windows = vim.fn.has("win32") == 1
local expected = {
  [" ff"] = windows and "Find Files" or "Find Files (FFF)",
  [" sg"] = windows and "Grep" or "Grep (FFF)",
  [" fe"] = "Explorer (Root Dir)",
  [" aa"] = "Toggle Pi",
  [" af"] = "Send File",
  [" at"] = "Send Position",
  [" qs"] = "Restore Session",
  [" qS"] = "Select Session",
  [" cf"] = "Format",
  [" sr"] = "Search and Replace",
  [" xx"] = "Diagnostics (Trouble)",
  [" st"] = "Todo",
  [" bp"] = "Toggle Pin",
  [" gL"] = "Git Log (cwd)",
  [" fF"] = "Find Files (cwd)",
  [" snh"] = "Message History",
}
local maps = {}
for _, map in ipairs(vim.api.nvim_get_keymap("n")) do maps[map.lhs] = map.desc end
for lhs, desc in pairs(expected) do assert(maps[lhs] == desc, lhs .. " mapping missing") end
assert(vim.fn.maparg("jk", "i") ~= "", "jk mapping missing")
assert(maps[" e"] == "Explorer (Root Dir)" and maps[" E"] == "Explorer (cwd)", "explorer aliases missing")
assert(maps.H == "Prev Buffer" and maps.L == "Next Buffer", "buffer navigation missing")
assert(maps["s"] == "Flash" and maps["S"] == "Flash Treesitter", "Flash mappings missing")
assert(maps["]t"] == "Next Todo Comment" and maps["[t"] == "Previous Todo Comment", "Todo navigation missing")
assert(maps["g<C-A>"] == "Increment" and maps["g<C-X>"] == "Decrement", "Dial sequence mappings missing")
assert(vim.fn.maparg("gp", "n") ~= "" and vim.fn.maparg("]p", "n") ~= "", "Yanky paste mappings missing")

local lazy = require("lazy.core.config")
assert(not lazy.plugins.LazyVim, "LazyVim must not be loaded")
for _, plugin in ipairs({
  "blink.cmp",
  "catppuccin",
  "conform.nvim",
  "flash.nvim",
  "grug-far.nvim",
  "gitsigns.nvim",
  "mason.nvim",
  "mini.hipatterns",
  "mini.surround",
  "noice.nvim",
  "nvim-lint",
  "nvim-lspconfig",
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "nvim-ts-autotag",
  "persistence.nvim",
  "render-markdown.nvim",
  "snacks.nvim",
  "todo-comments.nvim",
  "trouble.nvim",
  "ts-comments.nvim",
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
for _, name in ipairs({ "raw_checktime", "raw_highlight_yank", "raw_resize_splits", "raw_last_loc", "raw_auto_create_dir" }) do
  assert(#vim.api.nvim_get_autocmds({ group = name }) > 0, name .. " autocmd missing")
end
assert(lazy.plugins["snacks.nvim"]._.loaded, "Snacks must load dashboard")
assert(Snacks.config.dashboard.enabled ~= false, "dashboard missing")
print("RAW_CONFIG_OK")
