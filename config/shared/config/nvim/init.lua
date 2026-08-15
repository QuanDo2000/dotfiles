vim.g.raw_neovim = true
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.snacks_animate = false

local opt = vim.opt
opt.autowrite = true
opt.clipboard = "unnamedplus"
opt.completeopt = "menu,menuone,noselect"
opt.conceallevel = 2
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.fillchars = { foldopen = "", foldclose = "", fold = " ", foldsep = " ", diff = "╱", eob = " " }
opt.foldlevel = 99
opt.foldmethod = "indent"
opt.foldtext = ""
opt.formatoptions = "jcroqlnt"
opt.grepformat = "%f:%l:%c:%m"
opt.grepprg = "rg --vimgrep"
opt.ignorecase = true
opt.inccommand = "nosplit"
opt.jumpoptions = "view"
opt.laststatus = 3
opt.linebreak = true
opt.list = true
opt.mouse = "a"
opt.number = true
opt.relativenumber = true
opt.pumblend = 10
opt.pumheight = 10
opt.ruler = false
opt.scrolloff = 4
opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }
opt.shiftround = true
opt.showmode = false
opt.shiftwidth = 2
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.smartcase = true
opt.smartindent = true
opt.smoothscroll = true
opt.spelllang = { "en" }
opt.splitbelow = true
opt.splitkeep = "screen"
opt.splitright = true
opt.tabstop = 2
opt.termguicolors = true
opt.timeoutlen = 300
opt.undofile = true
opt.undolevels = 10000
opt.updatetime = 200
opt.virtualedit = "block"
opt.wildmode = "longest:full,full"
opt.winminwidth = 5
opt.wrap = false
vim.g.markdown_recommended_style = 0

local mode_names = {
  n = "NORMAL", i = "INSERT", v = "VISUAL", V = "V-LINE", ["\22"] = "V-BLOCK",
  c = "COMMAND", s = "SELECT", S = "S-LINE", ["\19"] = "S-BLOCK", R = "REPLACE", r = "PROMPT", t = "TERMINAL",
}
local function statusline_highlights()
  vim.api.nvim_set_hl(0, "RawStatusMode", { link = "Function" })
  vim.api.nvim_set_hl(0, "RawStatusGit", { link = "Special" })
  vim.api.nvim_set_hl(0, "RawStatusFile", { link = "StatusLine" })
  vim.api.nvim_set_hl(0, "RawStatusMeta", { link = "Comment" })
  vim.api.nvim_set_hl(0, "RawStatusPosition", { link = "Type" })
end
statusline_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = statusline_highlights })
function _G.raw_statusline()
  local buffer = vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
  local mode = vim.api.nvim_get_mode().mode
  local git = vim.b[buffer].gitsigns_status_dict or {}
  local branch = vim.b[buffer].gitsigns_head
  local diagnostics = vim.diagnostic.count(buffer)
  local parts = { "%#RawStatusMode# 󰘧 ", mode_names[mode] or mode_names[mode:sub(1, 1)] or mode:upper() }
  if branch and branch ~= "" then parts[#parts + 1] = ("%%#RawStatusGit#   %s +%d ~%d -%d"):format(branch:gsub("%%", "%%%%"), git.added or 0, git.changed or 0, git.removed or 0) end
  if (diagnostics[vim.diagnostic.severity.ERROR] or 0) > 0 then parts[#parts + 1] = "%#DiagnosticError# 󰅚 " .. diagnostics[vim.diagnostic.severity.ERROR] end
  if (diagnostics[vim.diagnostic.severity.WARN] or 0) > 0 then parts[#parts + 1] = "%#DiagnosticWarn# 󰀪 " .. diagnostics[vim.diagnostic.severity.WARN] end
  parts[#parts + 1] = "%#RawStatusFile# %f %m%r%=%#RawStatusMeta# %{&fileencoding==#''?&encoding:&fileencoding} %{&fileformat} %{&filetype}%#RawStatusPosition# %l:%c %P "
  return table.concat(parts)
end
opt.statusline = "%!v:lua.raw_statusline()"

if os.getenv("SSH_TTY") then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
end

local roots = require("config.root")
local function root() return roots.get() end

local function map(mode, lhs, rhs, desc, options)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { desc = desc, silent = true }, options or {}))
end

map("i", "jk", "<Esc>", "Escape insert mode")
map("n", "<Esc>", "<cmd>nohlsearch<cr>", "Clear Search Highlight")
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", "Down", { expr = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", "Up", { expr = true })
map("n", "<C-h>", "<C-w>h", "Go to Left Window")
map("n", "<C-j>", "<C-w>j", "Go to Lower Window")
map("n", "<C-k>", "<C-w>k", "Go to Upper Window")
map("n", "<C-l>", "<C-w>l", "Go to Right Window")
map("n", "<C-Up>", "<cmd>resize +2<cr>", "Increase Window Height")
map("n", "<C-Down>", "<cmd>resize -2<cr>", "Decrease Window Height")
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", "Decrease Window Width")
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", "Increase Window Width")
map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", "Move Down")
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", "Move Up")
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", "Move Down")
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", "Move Up")
map("x", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", "Move Down")
map("x", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", "Move Up")
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", "Prev Buffer")
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", "Next Buffer")
map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", "Prev Buffer")
map("n", "]b", "<cmd>BufferLineCycleNext<cr>", "Next Buffer")
map("n", "<leader>bb", "<cmd>e #<cr>", "Switch to Other Buffer")
map("n", "<leader>`", "<cmd>e #<cr>", "Switch to Other Buffer")
map("n", "<leader>bd", function() Snacks.bufdelete() end, "Delete Buffer")
map("n", "<leader>bo", function() Snacks.bufdelete.other() end, "Delete Other Buffers")
map("n", "<leader>bi", function() Snacks.bufdelete.invisible() end, "Delete Invisible Buffers")
map("n", "<leader>bD", "<cmd>bd<cr>", "Delete Buffer and Window")
map("n", "<leader>qq", "<cmd>qa<cr>", "Quit All")
map("n", "<leader>cf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, "Format")
map("n", "<leader>cd", vim.diagnostic.open_float, "Line Diagnostics")
map("n", "[d", function() vim.diagnostic.jump({ count = -vim.v.count1, float = true }) end, "Previous Diagnostic")
map("n", "]d", function() vim.diagnostic.jump({ count = vim.v.count1, float = true }) end, "Next Diagnostic")
map("n", "[e", function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end, "Previous Error")
map("n", "]e", function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end, "Next Error")
map("n", "[w", function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end, "Previous Warning")
map("n", "]w", function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end, "Next Warning")
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", "Save File")
map("x", "<", "<gv", "Indent Left")
map("x", ">", ">gv", "Indent Right")
map("n", "<leader>l", "<cmd>Lazy<cr>", "Lazy")
map("n", "<leader>fn", "<cmd>enew<cr>", "New File")
map("n", "n", "'Nn'[v:searchforward].'zv'", "Next Search Result", { expr = true })
map("n", "N", "'nN'[v:searchforward].'zv'", "Previous Search Result", { expr = true })
map({ "x", "o" }, "n", "'Nn'[v:searchforward]", "Next Search Result", { expr = true })
map({ "x", "o" }, "N", "'nN'[v:searchforward]", "Previous Search Result", { expr = true })
map("i", ",", ",<C-g>u", "Undo Break")
map("i", ".", ".<C-g>u", "Undo Break")
map("i", ";", ";<C-g>u", "Undo Break")
map("n", "gco", "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", "Add Comment Below")
map("n", "gcO", "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", "Add Comment Above")
map("n", "<leader>-", "<C-w>s", "Split Window Below")
map("n", "<leader>|", "<C-w>v", "Split Window Right")
map("n", "<leader>wd", "<C-w>c", "Delete Window")
map("n", "<leader>xl", function() local open = vim.fn.getloclist(0, { winid = 0 }).winid ~= 0; pcall(open and vim.cmd.lclose or vim.cmd.lopen) end, "Location List")
map("n", "<leader>xq", function() local open = vim.fn.getqflist({ winid = 0 }).winid ~= 0; pcall(open and vim.cmd.cclose or vim.cmd.copen) end, "Quickfix List")
map("n", "<leader><tab><tab>", "<cmd>tabnew<cr>", "New Tab")
map("n", "<leader><tab>d", "<cmd>tabclose<cr>", "Close Tab")
map("n", "<leader><tab>]", "<cmd>tabnext<cr>", "Next Tab")
map("n", "<leader><tab>[", "<cmd>tabprevious<cr>", "Previous Tab")
map("n", "[q", function() if package.loaded.trouble and require("trouble").is_open() then require("trouble").prev({ skip_groups = true, jump = true }) else pcall(vim.cmd.cprev) end end, "Previous Trouble/Quickfix Item")
map("n", "]q", function() if package.loaded.trouble and require("trouble").is_open() then require("trouble").next({ skip_groups = true, jump = true }) else pcall(vim.cmd.cnext) end end, "Next Trouble/Quickfix Item")

if vim.fn.has("win32") == 1 then
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
  local commit = assert(lock["lazy.nvim"] and lock["lazy.nvim"].commit, "lazy.nvim lock is missing")
  local syncing = vim.env.DOTFILE_NVIM_SYNC == "1"
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    if not syncing then error("lazy.nvim is missing; run dotfile update") end
    vim.fn.mkdir(vim.fs.dirname(lazypath), "p")
    vim.fn.system({ "git", "clone", "--filter=blob:none", "--no-checkout", "https://github.com/folke/lazy.nvim.git", lazypath })
    if vim.v.shell_error ~= 0 then vim.fn.delete(lazypath, "rf"); error("Failed to clone lazy.nvim") end
  end
  if syncing then
    vim.fn.system({ "git", "-C", lazypath, "fetch", "--filter=blob:none", "origin" })
    if vim.v.shell_error ~= 0 then error("Failed to fetch lazy.nvim") end
    vim.fn.system({ "git", "-C", lazypath, "checkout", "--force", commit })
    if vim.v.shell_error ~= 0 then error("Failed to checkout locked lazy.nvim") end
  end
  vim.opt.rtp:prepend(lazypath)
end

local ok, lazy = pcall(require, "lazy")
if not ok then error("lazy.nvim is missing; run dotfile update") end

vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin" .. (vim.fn.has("win32") == 1 and ";" or ":") .. vim.env.PATH

local plugins = {
  { "folke/lazy.nvim", enabled = vim.fn.has("win32") == 1 },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = vim.env.DOTFILE_NVIM_SYNC == "1",
    priority = 1000,
    opts = {
      flavour = "macchiato",
      background = { light = "latte", dark = "macchiato" },
      custom_highlights = function(colors)
        return {
          WhichKeyIconAzure = { fg = colors.blue },
          WhichKeyIconBlue = { fg = colors.sky },
          WhichKeyIconCyan = { fg = colors.teal },
          WhichKeyIconGreen = { fg = colors.green },
          WhichKeyIconGrey = { fg = colors.text },
          WhichKeyIconOrange = { fg = colors.yellow },
          WhichKeyIconPurple = { fg = colors.peach },
          WhichKeyIconRed = { fg = colors.red },
          WhichKeyIconYellow = { fg = colors.yellow },
        }
      end,
    },
    config = function(_, options)
      require("catppuccin").setup(options)
      vim.cmd.colorscheme("catppuccin-macchiato")
    end,
  },
  {
    "folke/snacks.nvim",
    event = "VimEnter",
    opts = {
      bigfile = { enabled = true },
      explorer = {}, input = {}, picker = {}, quickfile = { enabled = true }, terminal = {}, notifier = {}, lazygit = {},
    },
    config = function(_, options)
      _G.Snacks = require("snacks")
      Snacks.setup(options)
      vim.notify = Snacks.notifier
    end,
  },
  {
    "dmtrKovalenko/fff.nvim",
    enabled = vim.fn.has("win32") ~= 1,
    version = "v0.10.3",
    build = function(plugin) require("config.sync").link_fff(plugin) end,
    opts = {
      frecency = { db_path = vim.env.FFF_FRECENCY_DB or vim.fn.expand("~/.local/state/fff/frecency") },
      history = { db_path = vim.env.FFF_HISTORY_DB or vim.fn.expand("~/.local/state/fff/history") },
    },
  },
  { "nvim-tree/nvim-web-devicons", enabled = false },
  {
    "nvim-mini/mini.icons",
    event = "VeryLazy",
    opts = {},
    init = function() package.preload["nvim-web-devicons"] = function() require("mini.icons").mock_nvim_web_devicons(); return package.loaded["nvim-web-devicons"] end end,
  },
  {
    "nvim-mini/mini.pairs",
    event = "InsertEnter",
    opts = { modes = { insert = true, command = true, terminal = false } },
    config = function(_, options)
      local pairs = require("mini.pairs")
      pairs.setup(options)
      local open = pairs.open
      pairs.open = function(pair, neigh_pattern)
        if vim.g.minipairs_disable or vim.b.minipairs_disable or vim.bo.filetype:match("^snacks_picker") then return pair:sub(1, 1) end
        local open_char = pair:sub(1, 1)
        local line = vim.api.nvim_get_current_line()
        local cursor = vim.api.nvim_win_get_cursor(0)
        if open_char == "`" and vim.bo.filetype == "markdown" and line:sub(1, cursor[2]):match("^%s*``") then
          return "`\n```" .. vim.keycode("<Up>")
        end
        local next_char = line:sub(vim.fn.col("."), vim.fn.col("."))
        if next_char:match("[%w%%%'%[%\"%.%`%$]") then return pair:sub(1, 1) end
        local ok, captures = pcall(vim.treesitter.get_captures_at_cursor, 0)
        if ok then for _, capture in ipairs(captures) do if capture.capture == "string" then return pair:sub(1, 1) end end end
        local _, opens = line:gsub(vim.pesc(pair:sub(1, 1)), "")
        local _, closes = line:gsub(vim.pesc(pair:sub(2, 2)), "")
        if opens < closes then return pair:sub(1, 1) end
        return open(pair, neigh_pattern)
      end
    end,
  },
  {
    "nvim-mini/mini.surround",
    event = "VeryLazy",
    opts = {
      mappings = {
        add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF", highlight = "gsh", replace = "gsr", update_n_lines = "gsn",
      },
    },
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    opts = {
      cmdline = {
        completion = {
          menu = {
            auto_show = function() return vim.fn.getcmdtype() == ":" end,
          },
        },
      },
      completion = { list = { selection = { auto_insert = true } } },
      keymap = { preset = "default", ["<C-e>"] = { "cancel", "fallback" } },
    },
  },
  { "folke/trouble.nvim", cmd = "Trouble", opts = { modes = { lsp = { win = { position = "right" } } } } },
  { "folke/todo-comments.nvim", event = "VeryLazy", opts = {} },
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    opts = {},
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "saghen/blink.cmp" },
    config = function()
      vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
      vim.lsp.config("lua_ls", { settings = { Lua = { workspace = { checkThirdParty = false }, hint = { enable = false } } } })
      vim.lsp.config("jsonls", {
        before_init = function(_, config) config.settings.json.schemas = require("schemastore").json.schemas() end,
        settings = { json = { validate = { enable = true } } },
      })
      vim.lsp.config("yamlls", {
        before_init = function(_, config) config.settings.yaml.schemas = require("schemastore").yaml.schemas() end,
        settings = { redhat = { telemetry = { enabled = false } }, yaml = { keyOrdering = false, schemaStore = { enable = false, url = "" } } },
      })
      vim.lsp.enable({ "bashls", "jsonls", "lua_ls", "marksman", "nil_ls", "taplo", "yamlls" })
    end,
  },
  { "b0o/SchemaStore.nvim", lazy = true },
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        markdown = { "prettier", "markdownlint-cli2" },
        ["markdown.mdx"] = { "prettier", "markdownlint-cli2" },
        nix = { "nixfmt" },
      },
      format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
    },
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("lint").linters_by_ft = { nix = vim.fn.executable("statix") == 1 and { "statix" } or {} }
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("raw_lint", { clear = true }),
        callback = function() require("lint").try_lint() end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = "VeryLazy",
    opts = { move = { set_jumps = true } },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = vim.env.DOTFILE_NVIM_SYNC == "1",
    build = function()
      require("nvim-treesitter").install({
        "bash", "diff", "git_config", "git_rebase", "gitattributes", "gitcommit", "gitignore", "json", "json5",
        "lua", "markdown", "markdown_inline", "nix", "query", "toml", "vim", "vimdoc", "yaml",
      }):wait(300000)
    end,
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
        end,
      })
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    event = "VeryLazy",
    opts = {
      on_attach = function(buffer)
        local gs = require("gitsigns")
        local function bmap(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = buffer, desc = desc }) end
        bmap("n", "]h", function() gs.nav_hunk("next") end, "Next Hunk")
        bmap("n", "[h", function() gs.nav_hunk("prev") end, "Previous Hunk")
        bmap({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
        bmap({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
        bmap("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk")
        bmap("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
      end,
    },
  },
  { "akinsho/bufferline.nvim", event = "VeryLazy", dependencies = { "mini.icons" }, opts = {} },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      icons = {
        rules = {
          { pattern = "hunk", icon = "󰊢 ", color = "orange" },
          { pattern = "prev", icon = " ", color = "cyan" },
          { pattern = "next", icon = " ", color = "cyan" },
          { pattern = "goto", icon = "󰜴 ", color = "blue" },
          { pattern = "surround", icon = "󰅪 ", color = "yellow" },
          { pattern = "fold", icon = " ", color = "purple" },
        },
      },
      spec = {
        {
          mode = { "n", "x" },
          { "<leader><tab>", group = "tabs" },
          { "<leader>a", group = "ai" },
          { "<leader>b", group = "buffer" },
          { "<leader>c", group = "code" },
          { "<leader>f", group = "file/find" },
          { "<leader>g", group = "git" },
          { "<leader>gh", group = "hunks" },
          { "<leader>q", group = "quit" },
          { "<leader>s", group = "search" },
          { "<leader>sn", group = "messages" },
          { "<leader>u", group = "ui" },
          { "<leader>x", group = "diagnostics/quickfix" },
          { "[", group = "prev" },
          { "]", group = "next" },
          { "g", group = "goto" },
          { "gs", group = "surround" },
          { "z", group = "fold" },
        },
      },
    },
  },
}

lazy.setup({
  spec = plugins,
  concurrency = os.getenv("DOTFILE_NVIM_SYNC") == "1" and 2 or nil,
  defaults = { lazy = true, version = false },
  checker = { enabled = false, notify = false },
  install = { missing = false, colorscheme = { "catppuccin-macchiato", "habamax" } },
  git = { timeout = os.getenv("DOTFILE_NVIM_SYNC") == "1" and 600 or 120 },
  performance = { rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" } } },
})

vim.diagnostic.config({ severity_sort = true, underline = true, virtual_text = { spacing = 4, source = "if_many", prefix = "●" } })
vim.filetype.add({ extension = { mdx = "markdown.mdx", rasi = "rasi", rofi = "rasi", wofi = "rasi" }, pattern = { [".*/waybar/config"] = "jsonc", [".*/hypr/.+%.conf"] = "hyprlang", ["%.env%.[%w_.-]+"] = "sh" } })

local pi = require("config.pi-terminal")
map({ "n", "t", "i", "x" }, "<C-.>", pi.focus, "Focus Pi")
map("n", "<leader>aa", pi.toggle, "Toggle Pi")
map({ "n", "x" }, "<leader>at", pi.send_position, "Send Position")
map("n", "<leader>af", pi.send_file, "Send File")
map("x", "<leader>av", pi.send_selection, "Send Selection")

if vim.fn.has("win32") ~= 1 then
  map("n", "<leader>ff", function() require("fff").find_files() end, "Find Files (FFF)")
  map("n", "<leader>sg", function() require("fff").live_grep() end, "Grep (FFF)")
else
  map("n", "<leader>ff", function() Snacks.picker.files({ cwd = root() }) end, "Find Files")
  map("n", "<leader>sg", function() Snacks.picker.grep({ cwd = root() }) end, "Grep")
end
map("n", "<leader><space>", function() Snacks.picker.files({ cwd = root() }) end, "Find Files (Root Dir)")
map("n", "<leader>/", function() Snacks.picker.grep({ cwd = root() }) end, "Grep (Root Dir)")
map("n", "<leader>,", function() Snacks.picker.buffers() end, "Buffers")
map("n", "<leader>fB", function() Snacks.picker.buffers({ hidden = true, nofile = true }) end, "Buffers (all)")
map("n", "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, "Find Config File")
map("n", "<leader>fF", function() Snacks.picker.files() end, "Find Files (cwd)")
map("n", "<leader>fg", function() Snacks.picker.git_files() end, "Find Files (git-files)")
map("n", "<leader>fr", function() Snacks.picker.recent() end, "Recent")
map("n", "<leader>fR", function() Snacks.picker.recent({ filter = { cwd = true } }) end, "Recent (cwd)")
map("n", "<leader>fp", function() Snacks.picker.projects() end, "Projects")
map("n", "<leader>e", function() Snacks.explorer({ cwd = root() }) end, "Explorer (Root Dir)")
map("n", "<leader>E", function() Snacks.explorer() end, "Explorer (cwd)")
map("n", "<leader>gg", function() Snacks.lazygit({ cwd = roots.git() }) end, "Lazygit (Root Dir)")
map("n", "<leader>gG", function() Snacks.lazygit() end, "Lazygit (cwd)")
map("n", "<leader>gs", function() Snacks.picker.git_status() end, "Git Status")
map("n", "<leader>gd", function() Snacks.picker.git_diff() end, "Git Diff")
map("n", "<leader>gD", function() Snacks.picker.git_diff({ base = "origin", group = true }) end, "Git Diff (origin)")
map("n", "<leader>gS", function() Snacks.picker.git_stash() end, "Git Stash")
map("n", "<leader>gL", function() Snacks.picker.git_log() end, "Git Log (cwd)")
map("n", "<leader>gl", function() Snacks.picker.git_log({ cwd = roots.git() }) end, "Git Log")
map("n", "<leader>gb", function() Snacks.picker.git_log_line() end, "Git Blame Line")
map("n", "<leader>gf", function() Snacks.picker.git_log_file() end, "Git Current File History")
map({ "n", "x" }, "<leader>gB", function() Snacks.gitbrowse() end, "Git Browse (open)")
map({ "n", "x" }, "<leader>gY", function() Snacks.gitbrowse({ open = function(url) vim.fn.setreg("+", url) end, notify = false }) end, "Git Browse (copy)")
map("n", "<leader>sb", function() Snacks.picker.lines() end, "Buffer Lines")
map("n", "<leader>sB", function() Snacks.picker.grep_buffers() end, "Grep Open Buffers")
map("n", "<leader>sG", function() Snacks.picker.grep() end, "Grep (cwd)")
map({ "n", "x" }, "<leader>sw", function() Snacks.picker.grep_word({ cwd = root() }) end, "Visual selection or word (Root Dir)")
map({ "n", "x" }, "<leader>sW", function() Snacks.picker.grep_word() end, "Visual selection or word (cwd)")
map("n", "<leader>sd", function() Snacks.picker.diagnostics() end, "Diagnostics")
map("n", "<leader>sD", function() Snacks.picker.diagnostics_buffer() end, "Buffer Diagnostics")
map("n", "<leader>sh", function() Snacks.picker.help() end, "Help Pages")
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, "Keymaps")
map("n", "<leader>s\"", function() Snacks.picker.registers() end, "Registers")
map("n", "<leader>sj", function() Snacks.picker.jumps() end, "Jumps")
map("n", "<leader>sl", function() Snacks.picker.loclist() end, "Location List")
map("n", "<leader>sm", function() Snacks.picker.marks() end, "Marks")
map("n", "<leader>sR", function() Snacks.picker.resume() end, "Resume")
map("n", "<leader>sq", function() Snacks.picker.qflist() end, "Quickfix List")
map("n", "<leader>su", function() Snacks.picker.undo() end, "Undotree")
map("n", "<leader>uC", function() Snacks.picker.colorschemes() end, "Colorschemes")
map("n", "<leader>n", function() Snacks.picker.notifications() end, "Notification History")
map("n", "<leader>up", function() vim.g.minipairs_disable = not vim.g.minipairs_disable; vim.notify("Mini Pairs " .. (vim.g.minipairs_disable and "disabled" or "enabled")) end, "Toggle Mini Pairs")
map("n", "<leader>un", function() Snacks.notifier.hide() end, "Dismiss All Notifications")
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", "Diagnostics (Trouble)")
map("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", "Buffer Diagnostics (Trouble)")
map("n", "<leader>cs", "<cmd>Trouble symbols toggle<cr>", "Symbols (Trouble)")
map("n", "<leader>cS", "<cmd>Trouble lsp toggle<cr>", "LSP references/definitions/... (Trouble)")
map("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", "Location List (Trouble)")
map("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", "Quickfix List (Trouble)")
map("n", "]t", function() require("todo-comments").jump_next() end, "Next Todo Comment")
map("n", "[t", function() require("todo-comments").jump_prev() end, "Previous Todo Comment")
map("n", "<leader>xt", "<cmd>Trouble todo toggle<cr>", "Todo (Trouble)")
map("n", "<leader>xT", "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>", "Todo/Fix/Fixme (Trouble)")
map("n", "<leader>st", function() Snacks.picker.todo_comments() end, "Todo")
map("n", "<leader>sT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end, "Todo/Fix/Fixme")
map("n", "<leader>snh", "<cmd>messages<cr>", "Message History")
map("n", "<leader>snl", function() vim.cmd("messages"); vim.cmd.normal("G") end, "Last Message")
map("n", "<leader>fT", function() Snacks.terminal() end, "Terminal (cwd)")
map("n", "<leader>ft", function() Snacks.terminal(nil, { cwd = root() }) end, "Terminal (Root Dir)")
map({ "n", "t" }, "<C-/>", function() Snacks.terminal.focus(nil, { cwd = root() }) end, "Terminal (Root Dir)")

for lhs, command, desc in pairs({
  ["<leader>bp"] = { "BufferLineTogglePin", "Toggle Pin" }, ["<leader>bP"] = { "BufferLineGroupClose ungrouped", "Delete Non-Pinned Buffers" },
  ["<leader>br"] = { "BufferLineCloseRight", "Delete Buffers to the Right" }, ["<leader>bl"] = { "BufferLineCloseLeft", "Delete Buffers to the Left" },
  ["[B"] = { "BufferLineMovePrev", "Move buffer prev" }, ["]B"] = { "BufferLineMoveNext", "Move buffer next" }, ["<leader>bj"] = { "BufferLinePick", "Pick Buffer" },
}) do map("n", lhs, "<cmd>" .. command[1] .. "<cr>", command[2]) end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local function lmap(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc }) end
    lmap("n", "gd", function() Snacks.picker.lsp_definitions() end, "Goto Definition")
    lmap("n", "gr", function() Snacks.picker.lsp_references() end, "References")
    lmap("n", "gI", function() Snacks.picker.lsp_implementations() end, "Goto Implementation")
    lmap("n", "gy", function() Snacks.picker.lsp_type_definitions() end, "Goto Type Definition")
    lmap("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
    lmap("n", "K", vim.lsp.buf.hover, "Hover")
    lmap("n", "gK", vim.lsp.buf.signature_help, "Signature Help")
    lmap("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
    lmap("n", "<leader>ss", function() Snacks.picker.lsp_symbols() end, "LSP Symbols")
    lmap("n", "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, "LSP Workspace Symbols")
    lmap("n", "gai", function() Snacks.picker.lsp_incoming_calls() end, "Calls Incoming")
    lmap("n", "gao", function() Snacks.picker.lsp_outgoing_calls() end, "Calls Outgoing")
    lmap({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
    lmap("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
    if vim.lsp.inlay_hint then vim.lsp.inlay_hint.enable(false, { bufnr = event.buf }) end
  end,
})

local movements = {
  goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
  goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
  goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
  goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
}
for method, keys in pairs(movements) do
  for lhs, query in pairs(keys) do
    map({ "n", "x", "o" }, lhs, function()
      if vim.wo.diff and lhs:find("[cC]") then return vim.cmd("normal! " .. lhs) end
      require("nvim-treesitter-textobjects.move")[method](query, "textobjects")
    end, (lhs:sub(1, 1) == "[" and "Previous " or "Next ") .. query:gsub("@", ""):gsub("%..*", ""))
  end
end

local function augroup(name) return vim.api.nvim_create_augroup("raw_" .. name, { clear = true }) end
vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, { group = augroup("checktime"), callback = function() if vim.o.buftype ~= "nofile" then vim.cmd.checktime() end end })
vim.api.nvim_create_autocmd("TextYankPost", { group = augroup("highlight_yank"), callback = function() (vim.hl or vim.highlight).on_yank() end })
vim.api.nvim_create_autocmd("VimResized", { group = augroup("resize_splits"), callback = function() local tab = vim.fn.tabpagenr(); vim.cmd("tabdo wincmd ="); vim.cmd("tabnext " .. tab) end })
vim.api.nvim_create_autocmd("BufReadPost", { group = augroup("last_loc"), callback = function(event)
  if vim.bo[event.buf].filetype == "gitcommit" or vim.b[event.buf].raw_last_loc then return end
  vim.b[event.buf].raw_last_loc = true
  local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
  if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(event.buf) then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
end })
vim.api.nvim_create_autocmd("FileType", { group = augroup("close_with_q"), pattern = { "checkhealth", "gitsigns-blame", "help", "lspinfo", "notify", "qf", "startuptime", "tsplayground" }, callback = function(event)
  vim.bo[event.buf].buflisted = false
  vim.schedule(function() vim.keymap.set("n", "q", function() vim.cmd.close(); pcall(vim.api.nvim_buf_delete, event.buf, { force = true }) end, { buffer = event.buf, silent = true }) end)
end })
vim.api.nvim_create_autocmd("FileType", { group = augroup("man_unlisted"), pattern = "man", callback = function(event) vim.bo[event.buf].buflisted = false end })
vim.api.nvim_create_autocmd("FileType", { group = augroup("wrap_spell"), pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" }, callback = function() vim.opt_local.wrap = true; vim.opt_local.spell = true end })
vim.api.nvim_create_autocmd("FileType", { group = augroup("json_conceal"), pattern = { "json", "jsonc", "json5" }, callback = function() vim.opt_local.conceallevel = 0 end })
vim.api.nvim_create_autocmd("BufWritePre", { group = augroup("auto_create_dir"), callback = function(event)
  if event.match:match("^%w%w+:[\\/][\\/]") then return end
  local file = (vim.uv or vim.loop).fs_realpath(event.match) or event.match
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
end })
