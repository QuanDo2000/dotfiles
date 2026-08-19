local module = assert(os.getenv("NVIM_SYNC_MODULE"), "NVIM_SYNC_MODULE missing")
local calls = {}
local plugins = { sample = { _ = { tasks = {} } } }
local lockfile = os.tmpname()
local lazy_options = { lockfile = lockfile }
vim.fn.writefile({ "reviewed" }, lockfile)
local packages = {}
local requested = {}
local refresh_ok, refresh_calls = true, 0

local lock = { lock = {}, _loaded = false }
function lock.load()
  if lock._loaded then return end
  lock.lock = { sample = vim.fn.readfile(lockfile)[1] }
  lock._loaded = true
end
package.preload["lazy.manage.lock"] = function() return lock end

local function runner(name)
  return {
    wait = function(self)
      calls[#calls + 1] = name
      return self
    end,
  }
end

package.preload["lazy"] = function()
  return {
    install = function(options)
      assert(options.wait and options.show == false and options.lockfile)
      local lazy_lock = require("lazy.manage.lock")
      lazy_lock.lock, lazy_lock._loaded = { sample = "stale" }, true
      vim.fn.writefile({ "stale" }, lockfile)
      return runner("install")
    end,
    restore = function(options)
      assert(options.wait and options.show == false)
      local lazy_lock = require("lazy.manage.lock")
      lazy_lock.load()
      assert(lazy_lock.lock.sample == "reviewed", "reviewed lock cache must be restored before Lazy restore")
      vim.fn.writefile({ "normalized" }, lockfile)
      return runner("restore")
    end,
    clean = function(options)
      assert(options.wait and options.show == false)
      vim.fn.writefile({ "normalized" }, lockfile)
      return runner("clean")
    end,
    load = function(options)
      assert(options.wait and #options.plugins == 1)
      calls[#calls + 1] = options.plugins[1]
    end,
  }
end
package.preload["lazy.core.config"] = function() return { plugins = plugins, options = lazy_options } end
package.preload["mason-registry"] = function()
  return {
    refresh = function(callback)
      refresh_calls = refresh_calls + 1
      if refresh_ok then callback() else callback(false, "refresh exploded") end
    end,
    get_package = function(name)
      requested[name] = true
      packages[name] = packages[name] or {
        installed = false,
        is_installed = function(self) return self.installed end,
        install = function(self, _, callback)
          self.installed = true
          callback(true)
        end,
      }
      return packages[name]
    end,
  }
end

local executable, has = vim.fn.executable, vim.fn.has
local has_nix, is_windows = false, true
vim.fn.executable = function(name)
  if name == "nix" then return has_nix and 1 or 0 end
  return executable(name)
end
vim.fn.has = function(name)
  if name == "win32" then return is_windows and 1 or 0 end
  if name == "mac" then return 0 end
  return has(name)
end

local sync = dofile(module)
local linked, link_error = pcall(sync.link_fff, { dir = vim.fn.tempname() })
assert(not linked and tostring(link_error):find("Nix-managed fff.nvim backend is missing", 1, true), "missing fff backend must fail before sync")
sync.plugins(true)
assert(vim.deep_equal(calls, { "install", "restore", "clean" }), "plugin sync must install, restore, then clean")
assert(vim.fn.readfile(lockfile)[1] == "reviewed", "plugin sync must preserve reviewed lock")

plugins.sample._.tasks = {
  {
    has_errors = function() return true end,
    output = function() return "build exploded" end,
  },
}
local ok, err = pcall(sync.plugins, false)
assert(not ok and tostring(err):find("build exploded", 1, true), "Lazy task errors must fail sync")
assert(vim.fn.readfile(lockfile)[1] == "reviewed", "failed plugin sync must preserve reviewed lock")
plugins.sample._.tasks = {}

sync.tools()
for _, name in ipairs({
  "json-lsp", "lua-language-server", "markdownlint-cli2", "marksman",
  "prettier", "stylua", "taplo", "yaml-language-server",
}) do
  assert(requested[name], name .. " was not provisioned")
  assert(packages[name].installed, name .. " was not verified")
end
assert(not requested["bash-language-server"], "bash-language-server must remain platform-managed")
assert(not requested["nil"], "nil must remain platform-managed")
assert(not requested.nixfmt, "nixfmt must not be provisioned on Windows")
assert(calls[#calls] == "mason.nvim", "Mason must load only for explicit tool sync")

has_nix, is_windows = true, false
sync.tools()
assert(not requested["nil"], "nil must remain platform-managed when nix is available")
assert(not requested.nixfmt, "nixfmt must remain platform-managed off Windows")
local initial_refreshes = refresh_calls
sync.tools()
assert(refresh_calls == initial_refreshes, "verified tools must not refresh registry")

local required_parsers = {
  "bash", "diff", "git_config", "git_rebase", "gitattributes", "gitcommit", "gitignore", "json", "json5",
  "lua", "markdown", "markdown_inline", "nix", "query", "toml", "vim", "vimdoc", "yaml",
}
local installed_parsers = {}
local parser_info_dir = vim.fn.tempname()
local parser_configs = {}
vim.fn.mkdir(parser_info_dir, "p")
for _, name in ipairs(required_parsers) do parser_configs[name] = { install_info = { revision = "rev" } } end
local function install_parsers(names)
  return {
    wait = function()
      for _, name in ipairs(names) do
        installed_parsers[name] = true
        vim.fn.writefile({ "rev" }, parser_info_dir .. "/" .. name .. ".revision")
      end
    end,
  }
end
package.preload["nvim-treesitter"] = function()
  return {
    get_installed = function()
      local names = {}
      for name in pairs(installed_parsers) do names[#names + 1] = name end
      return names
    end,
    install = install_parsers,
    update = install_parsers,
  }
end
package.preload["nvim-treesitter.parsers"] = function() return parser_configs end
package.preload["nvim-treesitter.config"] = function()
  return { get_install_dir = function() return parser_info_dir end }
end
sync.parsers()
for _, name in ipairs(required_parsers) do assert(installed_parsers[name], name .. " parser was not installed") end

lazy_options.root = vim.fn.tempname()
plugins.sample.dir = lazy_options.root .. "/sample"
plugins["fff.nvim"] = { dir = lazy_options.root .. "/fff.nvim" }
package.preload.fff = function() return {} end
vim.fn.mkdir(plugins.sample.dir, "p")
vim.fn.mkdir(plugins["fff.nvim"].dir .. "/target/release", "p")
local fff_source = vim.fn.stdpath("config") .. "/fff-nvim-backend"
local fff_target = plugins["fff.nvim"].dir .. "/target/release/libfff_nvim.so"
vim.fn.mkdir(vim.fs.dirname(fff_source), "p")
vim.fn.writefile({ "backend" }, fff_source)
assert((vim.uv or vim.loop).fs_symlink(fff_source, fff_target))
vim.fn.writefile({ '{"sample":{"commit":"abc"},"fff.nvim":{"commit":"abc"}}' }, lockfile)
local system = vim.system
vim.system = function(command)
  return {
    wait = function()
      if command[#command] == "HEAD" then return { code = 0, stdout = "abc\n" } end
      return { code = 0, stdout = "" }
    end,
  }
end
is_windows = false
assert(sync.runtime_complete(), "matching plugins, tools, parsers, and FFF backend must be current")
plugins.unlocked = { dir = lazy_options.root .. "/unlocked" }
assert(not sync.runtime_complete(), "enabled plugin missing from lock must make runtime stale")
plugins.unlocked = nil
package.loaded.fff, package.preload.fff = nil, function() error("broken backend") end
assert(not sync.runtime_complete(), "unloadable FFF backend must make runtime stale")
package.preload.fff = function() return {} end
vim.fn.writefile({ "stale" }, parser_info_dir .. "/lua.revision")
assert(not sync.runtime_complete(), "stale parser revision must make runtime stale")
sync.parsers()
assert(vim.fn.readfile(parser_info_dir .. "/lua.revision")[1] == "rev", "parser sync must update stale revisions")
vim.fn.mkdir(lazy_options.root .. "/stale-plugin", "p")
assert(not sync.runtime_complete(), "unmanaged plugin directory must make runtime stale")
vim.fn.delete(lazy_options.root .. "/stale-plugin", "rf")
installed_parsers.lua = nil
assert(not sync.runtime_complete(), "missing parser must make runtime stale")
installed_parsers.lua = true
packages.prettier.installed = false
assert(not sync.runtime_complete(), "missing Mason package must make runtime stale")
packages.prettier.installed = true
vim.system = function()
  return { wait = function() return { code = 0, stdout = "wrong\n" } end }
end
assert(not sync.runtime_complete(), "wrong plugin commit must make runtime stale")
vim.system = system

packages.prettier.installed = false
refresh_ok = false
ok, err = pcall(sync.tools)
assert(not ok and tostring(err):find("registry refresh failed", 1, true), "registry failure must be clear")
vim.fn.executable, vim.fn.has = executable, has
vim.fn.delete(lockfile)
vim.fn.delete(lazy_options.root, "rf")
vim.fn.delete(parser_info_dir, "rf")
print("NVIM_SYNC_OK")
