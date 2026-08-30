local module = assert(os.getenv("NVIM_SYNC_MODULE"), "NVIM_SYNC_MODULE missing")
local calls = {}
local plugins = { sample = { _ = { tasks = {} } } }
local lockfile = os.tmpname()
local lazy_options = { lockfile = lockfile }
vim.fn.writefile({ "reviewed" }, lockfile)
local packages = {}
local requested = {}
local refresh_ok, refresh_calls = true, 0
local registry_current = true
local tool_pins = {
  ["json-lsp"] = "1.0", ["lua-language-server"] = "1.0", ["markdownlint-cli2"] = "1.0",
  marksman = "1.0", prettier = "1.0", stylua = "1.0", taplo = "1.0", ["yaml-language-server"] = "1.0",
}

package.preload["config.mason"] = function()
  return {
    tools = function() return tool_pins end,
    registry_current = function() return registry_current end,
  }
end

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
      if refresh_ok then registry_current = true; callback() else callback(false, "refresh exploded") end
    end,
    get_package = function(name)
      requested[name] = true
      packages[name] = packages[name] or {
        installed = false,
        version = nil,
        installs = 0,
        uninstalls = 0,
        is_installed = function(self) return self.installed end,
        get_installed_version = function(self) return self.version end,
        install = function(self, options, callback)
          assert(options.version == tool_pins[name], name .. " must install its pinned version")
          self.installed, self.version, self.installs = true, options.version, self.installs + 1
          callback(true)
        end,
        uninstall = function(self, _, callback)
          self.installed, self.version, self.uninstalls = false, nil, self.uninstalls + 1
          callback(true)
        end,
      }
      return packages[name]
    end,
  }
end

local has = vim.fn.has
local is_windows = true
vim.fn.has = function(name)
  if name == "win32" then return is_windows and 1 or 0 end
  if name == "mac" then return 0 end
  return has(name)
end

local sync = dofile(module)
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
for name, version in pairs(tool_pins) do
  assert(requested[name], name .. " was not provisioned")
  assert(packages[name].installed and packages[name].version == version, name .. " was not pinned")
end
assert(not requested["bash-language-server"], "bash-language-server must remain platform-managed")
assert(calls[#calls] == "mason.nvim", "Mason must load only for explicit tool sync")

packages.prettier.version = "0.9"
local prettier_installs = packages.prettier.installs
sync.tools()
assert(packages.prettier.version == tool_pins.prettier, "stale Mason tool must update to its pin")
assert(packages.prettier.installs == prettier_installs + 1, "stale Mason tool must reinstall")

local initial_refreshes = refresh_calls
sync.tools()
assert(refresh_calls == initial_refreshes + 1, "tool sync must refresh the pinned registry")

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
vim.fn.mkdir(plugins.sample.dir, "p")
vim.fn.writefile({ '{"sample":{"commit":"abc"}}' }, lockfile)
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
assert(sync.runtime_complete(), "matching plugins, tools, and parsers must be current")
plugins.unlocked = { dir = lazy_options.root .. "/unlocked" }
assert(not sync.runtime_complete(), "enabled plugin missing from lock must make runtime stale")
plugins.unlocked = nil
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
packages.prettier.installed, packages.prettier.version = true, tool_pins.prettier
packages.prettier.version = "0.9"
assert(not sync.runtime_complete(), "wrong Mason package version must make runtime stale")
packages.prettier.version = tool_pins.prettier
registry_current = false
assert(not sync.runtime_complete(), "wrong Mason registry version must make runtime stale")
registry_current = true
vim.system = function()
  return { wait = function() return { code = 0, stdout = "wrong\n" } end }
end
assert(not sync.runtime_complete(), "wrong plugin commit must make runtime stale")
vim.system = system

packages.prettier.installed = false
refresh_ok = false
ok, err = pcall(sync.tools)
assert(not ok and tostring(err):find("registry refresh failed", 1, true), "registry failure must be clear")
vim.fn.has = has
vim.fn.delete(lockfile)
vim.fn.delete(lazy_options.root, "rf")
vim.fn.delete(parser_info_dir, "rf")
print("NVIM_SYNC_OK")
