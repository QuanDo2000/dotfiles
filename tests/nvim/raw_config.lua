assert(vim.g.raw_neovim == true, "raw Neovim marker missing")
assert(vim.g.mapleader == " ")
assert(vim.o.number and vim.o.relativenumber and vim.o.undofile)
assert(vim.o.clipboard == "unnamedplus")
assert(vim.o.splitbelow and vim.o.splitright and not vim.o.wrap)
assert(vim.o.autowrite and vim.o.linebreak and vim.o.shiftround and vim.o.smoothscroll)
assert(vim.o.conceallevel == 2 and vim.o.undolevels == 10000 and vim.o.virtualedit == "block")
assert(vim.o.laststatus == 3 and vim.o.statusline == "%!v:lua.raw_statusline()", "native global statusline missing")
vim.b.gitsigns_head = "main"
vim.b.gitsigns_status_dict = { added = 1, changed = 2, removed = 3 }
local diagnostic_namespace = vim.api.nvim_create_namespace("raw_statusline_test")
vim.diagnostic.set(diagnostic_namespace, 0, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "test" } })
local statusline = raw_statusline()
vim.diagnostic.reset(diagnostic_namespace, 0)
assert(statusline:find("%#RawStatusMode# 󰘧 NORMAL", 1, true), "styled statusline mode missing")
assert(statusline:find("%#RawStatusGit#   main +1 ~2 -3", 1, true), "styled statusline Git summary missing")
assert(statusline:match("%%#DiagnosticError# 󰅚 %d+"), "styled statusline diagnostics missing")
assert(statusline:find("%#RawStatusFile# %f", 1, true) and statusline:find("%#RawStatusPosition# %l:%c %P", 1, true), "styled statusline file position missing")
for _, group in ipairs({ "RawStatusMode", "RawStatusGit", "RawStatusFile", "RawStatusMeta", "RawStatusPosition" }) do
  assert(next(vim.api.nvim_get_hl(0, { name = group, link = false })), group .. " highlight missing")
end

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
assert(maps[" ,"] == "Buffers", "buffer picker mapping missing")
for _, lhs in ipairs({ " :", " s/", " sa", " sC", " sH", " sM", " fb", " fe", " fE", " sc" }) do
  assert(maps[lhs] == nil, lhs .. " mapping must stay removed")
end
assert(maps.H == "Prev Buffer" and maps.L == "Next Buffer", "buffer navigation missing")
for _, lhs in ipairs({ "s", "S" }) do
  assert(vim.fn.maparg(lhs, "n") == "", lhs .. " native mapping must stay unshadowed")
end
for _, mapping in ipairs({ { "s", "x" }, { "S", "x" }, { "s", "o" }, { "S", "o" }, { "r", "o" }, { "R", "o" }, { "R", "x" }, { "<C-Space>", "n" }, { "<C-Space>", "x" }, { "<C-Space>", "o" } }) do
  assert(vim.fn.maparg(mapping[1], mapping[2]) == "", mapping[1] .. " Flash mapping must stay removed")
end
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
assert(lazy.options.install.missing == false, "ordinary startup must not install plugins")
if not windows then
  assert(not vim.o.runtimepath:find(vim.fn.stdpath("data") .. "/lazy/lazy.nvim", 1, true), "Unix must use Nix-managed lazy.nvim")
end
local blink = lazy.plugins["blink.cmp"]
assert(vim.tbl_contains(blink.event, "CmdlineEnter"), "Blink should load for command-line completion")
assert(type(blink.opts.cmdline.completion.menu.auto_show) == "function", "Blink command-line suggestions must auto-show selectively")
local mason = lazy.plugins["mason.nvim"]
assert(vim.tbl_contains(mason.cmd, "Mason"), "Mason UI command missing")
assert(not mason.event, "Mason must not provision tools during startup")
assert(not mason._.loaded, "Mason must stay off file-open path")
assert(lazy.plugins["todo-comments.nvim"].event == "VeryLazy", "Todo Comments should load after startup")
assert(not lazy.plugins["todo-comments.nvim"]._.loaded, "Todo Comments must stay off file-open path")
assert(lazy.plugins["mini.icons"].event == "VeryLazy", "Mini Icons should load with UI plugins")
assert(not lazy.plugins["mini.icons"]._.loaded, "Mini Icons must stay off file-open path")
assert(lazy.plugins["gitsigns.nvim"].event == "VeryLazy", "Gitsigns should load after startup")
assert(not lazy.plugins["gitsigns.nvim"]._.loaded, "Gitsigns must stay off file-open path")
assert(lazy.plugins["snacks.nvim"].event == "VimEnter", "Snacks should load after file opening")
assert(not lazy.plugins["snacks.nvim"]._.loaded, "Snacks must stay off file-open path")
assert(vim.env.PATH:match("^" .. vim.pesc(vim.fn.stdpath("data") .. "/mason/bin")), "Mason bin missing from PATH")
if vim.env.RAW_CONFIG_PARSE_ONLY == "1" then
  print("RAW_CONFIG_OK")
  return
end
require("lazy").load({ plugins = { "nvim-lspconfig" } })
local servers = { "bashls", "jsonls", "lua_ls", "marksman", "taplo", "yamlls" }
if vim.fn.executable("nil") == 1 then servers[#servers + 1] = "nil_ls" end
for _, server in ipairs(servers) do assert(vim.lsp.is_enabled(server), server .. " should be enabled") end
assert(not vim.lsp.is_enabled("stylua"), "StyLua formatter must not enable as LSP")
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
  "gitsigns.nvim",
  "mason.nvim",
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
for _, plugin in ipairs({ "dial.nvim", "flash.nvim", "friendly-snippets", "grug-far.nvim", "lazydev.nvim", "lualine.nvim", "mason-lspconfig.nvim", "mini.ai", "mini.hipatterns", "noice.nvim", "nui.nvim", "nvim-ts-autotag", "persistence.nvim", "render-markdown.nvim", "ts-comments.nvim", "yanky.nvim" }) do
  assert(not lazy.plugins[plugin], plugin .. " must stay removed")
end
assert((not windows) == (lazy.plugins["fff.nvim"] and lazy.plugins["fff.nvim"].enabled ~= false), "fff.nvim platform gate is wrong")
require("lazy").load({ plugins = { "conform.nvim", "nvim-lint" } })
local conform = lazy.plugins["conform.nvim"].opts
assert(vim.deep_equal(conform.formatters_by_ft.markdown, { "prettier", "markdownlint-cli2" }), "Markdown formatter ownership changed")
assert(not conform.formatters, "Markdown formatter must not depend on stale diagnostics")
local lint = require("lint")
assert(not lint.linters_by_ft.markdown, "Markdownlint must have one owner")
local lint_events = {}
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = { "BufWritePre", "BufWritePost", "InsertLeave" } })) do
  if autocmd.desc == "Format on save" then lint_events.format_on_save = true end
  if autocmd.group_name == "raw_lint" then lint_events[autocmd.event] = true end
end
assert(lint_events.format_on_save, "format-on-save autocmd missing")
assert(lint_events.BufWritePost and not lint_events.InsertLeave, "lint must run only after writes")
for _, name in ipairs({ "raw_checktime", "raw_highlight_yank", "raw_resize_splits", "raw_last_loc", "raw_auto_create_dir" }) do
  assert(#vim.api.nvim_get_autocmds({ group = name }) > 0, name .. " autocmd missing")
end
require("lazy").load({ plugins = { "snacks.nvim" } })
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
