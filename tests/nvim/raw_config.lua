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
  [" aa"] = "Toggle Pi",
  [" af"] = "Send File",
  [" at"] = "Send Position",
  [" cf"] = "Format",
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
assert(maps[" e"] == "Explorer (Root Dir)" and maps[" E"] == "Explorer (cwd)", "explorer mappings missing")
assert(maps[" ,"] == "Buffers" and maps[" :"] == "Command History", "picker mappings missing")
for _, lhs in ipairs({ " fb", " fe", " fE", " sc" }) do
  assert(maps[lhs] == nil, lhs .. " duplicate mapping must stay removed")
end
assert(maps.H == "Prev Buffer" and maps.L == "Next Buffer", "buffer navigation missing")
assert(maps["s"] == "Flash" and maps["S"] == "Flash Treesitter", "Flash mappings missing")
assert(maps["]t"] == "Next Todo Comment" and maps["[t"] == "Previous Todo Comment", "Todo navigation missing")
assert(maps["<C-A>"] == nil and maps["<C-X>"] == nil, "native increment mappings must stay unshadowed")
assert(maps["g<C-A>"] == nil and maps["g<C-X>"] == nil, "Dial sequence mappings must stay removed")
for _, lhs in ipairs({ "y", "p", "P", "gp", "gP", "]p", "[p", "]P", "[P" }) do
  assert(vim.fn.maparg(lhs, "n") == "", lhs .. " native mapping must stay unshadowed")
end
assert(maps[" p"] == nil and maps["]y"] == nil and maps["[y"] == nil, "Yanky mappings must stay removed")
assert(maps[" <Tab><Tab>"] == "New Tab", "new tab mapping missing")
assert(maps[" <Tab>d"] == "Close Tab", "close tab mapping missing")
assert(maps[" <Tab>]"] == "Next Tab", "next tab mapping missing")
assert(maps[" <Tab>["] == "Previous Tab", "previous tab mapping missing")
for _, lhs in ipairs({ " <Tab>l", " <Tab>o", " <Tab>f" }) do
  assert(maps[lhs] == nil, lhs .. " redundant tab-page mapping must stay removed")
end

local lazy = require("lazy.core.config")
assert(not lazy.plugins.LazyVim, "LazyVim must not be loaded")
local which_key_opts = lazy.plugins["which-key.nvim"].opts
local which_key_groups = {}
for _, section in ipairs(which_key_opts.spec or {}) do
  for _, item in ipairs(section) do
    if item.group then which_key_groups[item[1]] = item.group end
  end
end
for prefix, group in pairs({
  ["<leader><tab>"] = "tabs",
  ["<leader>a"] = "ai",
  ["<leader>b"] = "buffer",
  ["<leader>c"] = "code",
  ["<leader>f"] = "file/find",
  ["<leader>g"] = "git",
  ["<leader>gh"] = "hunks",
  ["<leader>q"] = "quit",
  ["<leader>s"] = "search",
  ["<leader>sn"] = "messages",
  ["<leader>u"] = "ui",
  ["<leader>x"] = "diagnostics/quickfix",
  ["["] = "prev",
  ["]"] = "next",
  ["g"] = "goto",
  ["gs"] = "surround",
  ["z"] = "fold",
}) do
  assert(which_key_groups[prefix] == group, prefix .. " WhichKey group missing")
end
for pattern, icon in pairs({ hunk = "󰊢 ", prev = " ", next = " ", goto = "󰜴 ", surround = "󰅪 ", fold = " " }) do
  local resolved = require("which-key.icons").get({ desc = pattern })
  assert(resolved == icon, pattern .. " WhichKey icon missing")
end
vim.cmd.colorscheme("catppuccin-macchiato")
for target, source in pairs({
  WhichKeyIconAzure = "Function",
  WhichKeyIconBlue = "DiagnosticInfo",
  WhichKeyIconCyan = "DiagnosticHint",
  WhichKeyIconGreen = "DiagnosticOk",
  WhichKeyIconGrey = "Normal",
  WhichKeyIconOrange = "DiagnosticWarn",
  WhichKeyIconPurple = "Constant",
  WhichKeyIconRed = "DiagnosticError",
  WhichKeyIconYellow = "DiagnosticWarn",
}) do
  local actual = vim.api.nvim_get_hl(0, { name = target, link = false })
  local expected = vim.api.nvim_get_hl(0, { name = source, link = false })
  assert(actual.fg == expected.fg, target .. " color changed")
  assert(not actual.italic and not (actual.cterm and actual.cterm.italic), target .. " must not be italic")
end
for _, plugin in ipairs({
  "blink.cmp",
  "catppuccin",
  "conform.nvim",
  "flash.nvim",
  "gitsigns.nvim",
  "mason.nvim",
  "mini.hipatterns",
  "mini.surround",
  "nvim-lint",
  "nvim-lspconfig",
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "snacks.nvim",
  "todo-comments.nvim",
  "trouble.nvim",
}) do
  assert(lazy.plugins[plugin], plugin .. " missing")
end
for _, plugin in ipairs({ "dial.nvim", "friendly-snippets", "grug-far.nvim", "mini.ai", "noice.nvim", "nui.nvim", "nvim-ts-autotag", "persistence.nvim", "render-markdown.nvim", "ts-comments.nvim", "yanky.nvim" }) do
  assert(not lazy.plugins[plugin], plugin .. " must stay removed")
end
assert((not windows) == (lazy.plugins["fff.nvim"] and lazy.plugins["fff.nvim"].enabled ~= false), "fff.nvim platform gate is wrong")
require("lazy").load({ plugins = { "mini.hipatterns" } })
local highlighters = require("mini.hipatterns").config.highlighters
assert(highlighters.hex_color and highlighters.shorthand, "hex color highlighters missing")
assert(not highlighters.tailwind, "custom Tailwind color highlighter must stay removed")
require("lazy").load({ plugins = { "conform.nvim" } })
local format_on_save = false
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "BufWritePre" })) do
  if autocmd.desc == "Format on save" then format_on_save = true end
end
assert(format_on_save, "format-on-save autocmd missing")
for _, name in ipairs({ "raw_checktime", "raw_highlight_yank", "raw_resize_splits", "raw_last_loc", "raw_auto_create_dir" }) do
  assert(#vim.api.nvim_get_autocmds({ group = name }) > 0, name .. " autocmd missing")
end
assert(lazy.plugins["snacks.nvim"]._.loaded, "Snacks must load")
assert(not Snacks.config.dashboard.enabled, "startup dashboard must stay disabled")
for _, lhs in ipairs({ " sna", " snd", " snt" }) do
  assert(maps[lhs] == nil, lhs .. " Noice mapping must stay removed")
end
assert(vim.fn.maparg("<S-Enter>", "c") == "", "Noice command redirect must stay removed")
assert(maps[" sr"] == nil, "project-wide replace mapping must stay removed")
assert(maps[" um"] == nil, "Render Markdown mapping must stay removed")
for _, lhs in ipairs({ " qs", " qS", " ql", " qd" }) do
  assert(maps[lhs] == nil, lhs .. " session mapping must stay removed")
end
print("RAW_CONFIG_OK")
