local module = assert(os.getenv("NVIM_SYNC_MODULE"), "NVIM_SYNC_MODULE missing")
local calls = {}
local plugins = { sample = { _ = { tasks = {} } } }
local packages = {}
local requested = {}
local refresh_ok, refresh_calls = true, 0

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
      return runner("install")
    end,
    restore = function(options)
      assert(options.wait and options.show == false)
      return runner("restore")
    end,
    clean = function(options)
      assert(options.wait and options.show == false)
      return runner("clean")
    end,
    load = function(options)
      assert(options.wait and options.plugins[1] == "mason.nvim")
      calls[#calls + 1] = "mason"
    end,
  }
end
package.preload["lazy.core.config"] = function() return { plugins = plugins } end
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

local sync = dofile(module)
sync.plugins(true)
assert(vim.deep_equal(calls, { "install", "restore", "clean" }), "plugin sync must install, restore, then clean")

plugins.sample._.tasks = {
  {
    has_errors = function() return true end,
    output = function() return "build exploded" end,
  },
}
local ok, err = pcall(sync.plugins, false)
assert(not ok and tostring(err):find("build exploded", 1, true), "Lazy task errors must fail sync")
plugins.sample._.tasks = {}

sync.tools()
for _, name in ipairs({
  "bash-language-server", "json-lsp", "lua-language-server", "markdownlint-cli2", "marksman", "nil",
  "nixfmt", "prettier", "stylua", "taplo", "yaml-language-server",
}) do
  assert(requested[name], name .. " was not provisioned")
  assert(packages[name].installed, name .. " was not verified")
end
assert(calls[#calls] == "mason", "Mason must load only for explicit tool sync")
local initial_refreshes = refresh_calls
sync.tools()
assert(refresh_calls == initial_refreshes, "verified tools must not refresh registry")

packages.prettier.installed = false
refresh_ok = false
ok, err = pcall(sync.tools)
assert(not ok and tostring(err):find("registry refresh failed", 1, true), "registry failure must be clear")
print("NVIM_SYNC_OK")
