vim.g.raw_neovim = true
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.snacks_animate = false

local opt = vim.opt
opt.clipboard = "unnamedplus"
opt.completeopt = "menu,menuone,noselect"
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.ignorecase = true
opt.laststatus = 3
opt.list = true
opt.mouse = "a"
opt.number = true
opt.relativenumber = true
opt.scrolloff = 4
opt.showmode = false
opt.shiftwidth = 2
opt.signcolumn = "yes"
opt.smartcase = true
opt.smartindent = true
opt.splitbelow = true
opt.splitright = true
opt.tabstop = 2
opt.termguicolors = true
opt.timeoutlen = 300
opt.undofile = true
opt.updatetime = 200
opt.wrap = false

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

local function root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fs.dirname(file) or (vim.uv or vim.loop).cwd()
  return vim.fs.root(start, { ".git", "flake.nix" }) or (vim.uv or vim.loop).cwd()
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

map("i", "jk", "<Esc>", "Escape insert mode")
map("n", "<Esc>", "<cmd>nohlsearch<cr>", "Clear Search Highlight")
map("n", "<leader>qq", "<cmd>qa<cr>", "Quit All")
map("n", "<leader>cf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, "Format")
map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, "Previous Diagnostic")
map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next Diagnostic")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if vim.fn.has("win32") == 1 then
  local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
  local commit = assert(lock["lazy.nvim"] and lock["lazy.nvim"].commit, "lazy.nvim lock is missing")
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none", "--no-checkout", "https://github.com/folke/lazy.nvim.git", lazypath })
    if vim.v.shell_error ~= 0 then vim.fn.delete(lazypath, "rf"); error("Failed to clone lazy.nvim") end
  end
  vim.fn.system({ "git", "-C", lazypath, "checkout", "--force", commit })
  if vim.v.shell_error ~= 0 then error("Failed to checkout locked lazy.nvim") end
end
vim.opt.rtp:prepend(lazypath)

local ok, lazy = pcall(require, "lazy")
if not ok then error("lazy.nvim is missing; run dotfile update") end

local plugins = {
  { "folke/lazy.nvim", enabled = vim.fn.has("win32") == 1 },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = { flavour = "macchiato", background = { light = "latte", dark = "macchiato" } },
    config = function(_, options)
      require("catppuccin").setup(options)
      vim.cmd.colorscheme("catppuccin-macchiato")
    end,
  },
  {
    "folke/snacks.nvim",
    lazy = false,
    opts = { explorer = {}, picker = {}, terminal = {}, notifier = {}, lazygit = {} },
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
    build = function(plugin)
      local uv = vim.uv or vim.loop
      local source = vim.fn.stdpath("config") .. "/fff-nvim-backend"
      local extension = vim.fn.has("mac") == 1 and "dylib" or "so"
      local target = plugin.dir .. "/target/release/libfff_nvim." .. extension
      if not uv.fs_stat(source) then error("Nix-managed fff.nvim backend is missing: " .. source) end
      vim.fn.mkdir(vim.fs.dirname(target), "p")
      vim.fn.delete(target)
      local linked, err = uv.fs_symlink(source, target)
      if not linked then error("Failed to link fff.nvim backend: " .. (err or "unknown error")) end
    end,
    opts = {
      frecency = { db_path = vim.env.FFF_FRECENCY_DB or vim.fn.expand("~/.local/state/fff/frecency") },
      history = { db_path = vim.env.FFF_HISTORY_DB or vim.fn.expand("~/.local/state/fff/history") },
    },
  },
  { "nvim-tree/nvim-web-devicons", enabled = false },
  {
    "nvim-mini/mini.icons",
    lazy = false,
    opts = {},
    init = function() package.preload["nvim-web-devicons"] = function() require("mini.icons").mock_nvim_web_devicons(); return package.loaded["nvim-web-devicons"] end end,
  },
  { "nvim-mini/mini.pairs", event = "InsertEnter", opts = {} },
  {
    "nvim-mini/mini.ai",
    event = "VeryLazy",
    opts = function()
      local ai = require("mini.ai")
      return {
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter({ a = { "@block.outer", "@conditional.outer", "@loop.outer" }, i = { "@block.inner", "@conditional.inner", "@loop.inner" } }),
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          u = ai.gen_spec.function_call(),
          U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
        },
      }
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
    "nvim-mini/mini.hipatterns",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local hipatterns = require("mini.hipatterns")
      hipatterns.setup({ highlighters = { hex_color = hipatterns.gen_highlighter.hex_color() } })
    end,
  },
  {
    "saghen/blink.cmp",
    lazy = true,
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      completion = { list = { selection = { auto_insert = true } } },
      keymap = { preset = "default", ["<C-e>"] = { "cancel", "fallback" } },
    },
  },
  {
    "mason-org/mason.nvim",
    event = { "BufReadPre", "BufNewFile" },
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    config = function()
      require("mason").setup()
      require("mason-registry").refresh(function()
        for _, name in ipairs({ "markdownlint-cli2", "markdown-toc", "shellcheck", "shfmt", "stylua" }) do
          local package = require("mason-registry").get_package(name)
          if not package:is_installed() then package:install() end
        end
      end)
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason.nvim", "neovim/nvim-lspconfig", "saghen/blink.cmp" },
    opts = { ensure_installed = { "bashls", "jsonls", "lua_ls", "marksman", "nil_ls", "taplo", "yamlls" } },
    config = function(_, options)
      local capabilities = require("blink.cmp").get_lsp_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })
      vim.lsp.config("lua_ls", { settings = { Lua = { workspace = { checkThirdParty = false }, hint = { enable = false } } } })
      vim.lsp.config("jsonls", {
        before_init = function(_, config)
          config.settings.json.schemas = require("schemastore").json.schemas()
        end,
        settings = { json = { validate = { enable = true } } },
      })
      vim.lsp.config("yamlls", {
        before_init = function(_, config)
          config.settings.yaml.schemas = require("schemastore").yaml.schemas()
        end,
        settings = { redhat = { telemetry = { enabled = false } }, yaml = { keyOrdering = false, schemaStore = { enable = false, url = "" } } },
      })
      require("mason-lspconfig").setup(options)
    end,
  },
  { "b0o/SchemaStore.nvim", lazy = true },
  { "folke/lazydev.nvim", ft = "lua", opts = { library = { { path = "snacks.nvim", words = { "Snacks" } }, { path = "lazy.nvim", words = { "lazy" } } } } },
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      formatters = {
        ["markdown-toc"] = {
          condition = function(_, context)
            for _, line in ipairs(vim.api.nvim_buf_get_lines(context.buf, 0, -1, false)) do
              if line:find("<!%-%- toc %-%->") then return true end
            end
          end,
        },
        ["markdownlint-cli2"] = {
          condition = function(_, context)
            for _, diagnostic in ipairs(vim.diagnostic.get(context.buf)) do
              if diagnostic.source == "markdownlint" then return true end
            end
          end,
        },
      },
      formatters_by_ft = {
        lua = { "stylua" },
        markdown = { "prettier", "markdownlint-cli2", "markdown-toc" },
        ["markdown.mdx"] = { "prettier", "markdownlint-cli2", "markdown-toc" },
        nix = { "nixfmt" },
      },
      format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
    },
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("lint").linters_by_ft = { markdown = { "markdownlint-cli2" }, nix = { "statix" } }
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, { callback = function() require("lint").try_lint() end })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
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
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "markdown.mdx" },
    opts = { code = { sign = false, width = "block", right_pad = 1 }, heading = { sign = false, icons = {} }, checkbox = { enabled = false } },
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
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
  { "nvim-lualine/lualine.nvim", event = "VeryLazy", dependencies = { "mini.icons" }, opts = { options = { globalstatus = true } } },
  { "akinsho/bufferline.nvim", event = "VeryLazy", dependencies = { "mini.icons" }, opts = {} },
  { "folke/which-key.nvim", event = "VeryLazy", opts = { preset = "helix" } },
  {
    "gbprod/yanky.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = { system_clipboard = { sync_with_ring = not vim.env.SSH_CONNECTION }, highlight = { timer = 150 } },
  },
  {
    "monaqa/dial.nvim",
    event = "VeryLazy",
    config = function()
      local augend = require("dial.augend")
      require("dial.config").augends:register_group({ default = { augend.integer.alias.decimal_int, augend.integer.alias.hex, augend.date.alias["%Y/%m/%d"], augend.constant.alias.bool } })
    end,
  },
  { "folke/persistence.nvim", event = "BufReadPre", opts = {} },
}

lazy.setup({
  spec = plugins,
  defaults = { lazy = true, version = false },
  checker = { enabled = false, notify = false },
  install = { colorscheme = { "catppuccin-macchiato", "habamax" } },
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
map("n", "<leader>fb", function() Snacks.picker.buffers() end, "Buffers")
map("n", "<leader>fr", function() Snacks.picker.recent() end, "Recent")
map("n", "<leader>fe", function() Snacks.explorer({ cwd = root() }) end, "Explorer (Root Dir)")
map("n", "<leader>fE", function() Snacks.explorer() end, "Explorer (cwd)")
map("n", "<leader>e", function() Snacks.explorer({ cwd = root() }) end, "Explorer (Root Dir)")
map("n", "<leader>E", function() Snacks.explorer() end, "Explorer (cwd)")
map("n", "<leader>gg", function() Snacks.lazygit({ cwd = root() }) end, "Lazygit")
map("n", "<leader>gs", function() Snacks.picker.git_status() end, "Git Status")
map("n", "<leader>gd", function() Snacks.picker.git_diff() end, "Git Diff")
map("n", "<leader>sd", function() Snacks.picker.diagnostics() end, "Diagnostics")
map("n", "<leader>sh", function() Snacks.picker.help() end, "Help Pages")
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, "Keymaps")
map("n", "<leader>p", function() Snacks.picker.yanky() end, "Open Yank History")

map({ "n", "x" }, "y", "<Plug>(YankyYank)", "Yank Text")
map({ "n", "x" }, "p", "<Plug>(YankyPutAfter)", "Put Text After Cursor")
map({ "n", "x" }, "P", "<Plug>(YankyPutBefore)", "Put Text Before Cursor")
map("n", "[y", "<Plug>(YankyCycleForward)", "Cycle Forward Through Yank History")
map("n", "]y", "<Plug>(YankyCycleBackward)", "Cycle Backward Through Yank History")

local function dial(increment, g)
  local mode = vim.fn.mode(true)
  local visual = mode == "v" or mode == "V" or mode == "\22"
  return require("dial.map")[(increment and "inc" or "dec") .. (g and "_g" or "_") .. (visual and "visual" or "normal")]("default")
end
vim.keymap.set({ "n", "x" }, "<C-a>", function() return dial(true) end, { desc = "Increment", expr = true })
vim.keymap.set({ "n", "x" }, "<C-x>", function() return dial(false) end, { desc = "Decrement", expr = true })

map("n", "<leader>qs", function() require("persistence").load() end, "Restore Session")
map("n", "<leader>ql", function() require("persistence").load({ last = true }) end, "Restore Last Session")
map("n", "<leader>qd", function() require("persistence").stop() end, "Don't Save Current Session")

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local function lmap(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc }) end
    lmap("n", "gd", vim.lsp.buf.definition, "Goto Definition")
    lmap("n", "gr", vim.lsp.buf.references, "References")
    lmap("n", "gI", vim.lsp.buf.implementation, "Goto Implementation")
    lmap("n", "gy", vim.lsp.buf.type_definition, "Goto Type Definition")
    lmap("n", "K", vim.lsp.buf.hover, "Hover")
    lmap({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
    lmap("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
    if vim.lsp.inlay_hint then vim.lsp.inlay_hint.enable(false, { bufnr = event.buf }) end
  end,
})
