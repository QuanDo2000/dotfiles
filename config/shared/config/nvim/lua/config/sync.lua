local M = {}

local tools = {
  "bash-language-server",
  "json-lsp",
  "lua-language-server",
  "markdownlint-cli2",
  "marksman",
  "nil",
  "nixfmt",
  "prettier",
  "stylua",
  "taplo",
  "yaml-language-server",
}

local function lazy_errors()
  local errors = {}
  for name, plugin in pairs(require("lazy.core.config").plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      if task:has_errors() then errors[#errors + 1] = name .. ": " .. task:output(vim.log.levels.ERROR) end
    end
  end
  if #errors > 0 then error("Lazy sync failed:\n" .. table.concat(errors, "\n")) end
end

function M.link_fff(plugin)
  local uv = vim.uv or vim.loop
  local source = vim.fn.stdpath("config") .. "/fff-nvim-backend"
  local extension = vim.fn.has("mac") == 1 and "dylib" or "so"
  local target = plugin.dir .. "/target/release/libfff_nvim." .. extension
  if not uv.fs_stat(source) then error("Nix-managed fff.nvim backend is missing: " .. source) end
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  local temporary = target .. ".tmp." .. vim.fn.getpid()
  vim.fn.delete(temporary)
  local linked, err = uv.fs_symlink(source, temporary)
  if not linked then error("Failed to link fff.nvim backend: " .. (err or "unknown error")) end
  local renamed, rename_error = uv.fs_rename(temporary, target)
  if not renamed then
    vim.fn.delete(temporary)
    error("Failed to activate fff.nvim backend: " .. (rename_error or "unknown error"))
  end
end

function M.plugins(clean)
  local lazy = require("lazy")
  lazy.install({ wait = true, show = false, lockfile = true }):wait()
  lazy_errors()
  lazy.restore({ wait = true, show = false }):wait()
  lazy_errors()
  if clean then
    lazy.clean({ wait = true, show = false }):wait()
    lazy_errors()
  end

  local fff = require("lazy.core.config").plugins["fff.nvim"]
  if fff and fff.enabled ~= false then
    M.link_fff(fff)
    require("fff")
  end
end

function M.tools()
  require("lazy").load({ plugins = { "mason.nvim" }, wait = true })
  local registry = require("mason-registry")
  local function verified()
    for _, name in ipairs(tools) do
      local ok, package = pcall(registry.get_package, name)
      if not ok or not package:is_installed() then return false end
    end
    return true
  end
  if verified() then return end

  local done, failure = false, nil
  registry.refresh(function(success)
    if success == false then
      failure, done = "Mason registry refresh failed", true
      return
    end

    local ok, err = pcall(function()
      local missing = {}
      for _, name in ipairs(tools) do
        local package = registry.get_package(name)
        if not package:is_installed() then missing[#missing + 1] = package end
      end
      if #missing == 0 then
        done = true
        return
      end

      local pending = #missing
      for _, package in ipairs(missing) do
        package:install(nil, function(installed, install_error)
          if not installed then failure = tostring(install_error or (package.name .. " installation failed")) end
          pending = pending - 1
          if pending == 0 then done = true end
        end)
      end
    end)
    if not ok then failure, done = tostring(err), true end
  end)

  if not vim.wait(300000, function() return done end, 100) then error("Mason tool installation timed out") end
  if failure then error(failure) end
  if not verified() then error("Required Mason tools are missing after sync") end
end

return M
