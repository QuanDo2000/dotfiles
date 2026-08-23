local M = {}
local mason = require("config.mason")

local parsers = {
  "bash", "diff", "git_config", "git_rebase", "gitattributes", "gitcommit", "gitignore", "json", "json5",
  "lua", "markdown", "markdown_inline", "nix", "query", "toml", "vim", "vimdoc", "yaml",
}

local function restore_lock(path, contents)
  local temporary = path .. ".tmp." .. vim.fn.getpid()
  vim.fn.delete(temporary)
  if vim.fn.writefile(contents, temporary, "b") ~= 0 then error("Failed to stage reviewed Neovim lock") end
  vim.fn.setfperm(temporary, vim.fn.getfperm(path))
  local renamed, err = (vim.uv or vim.loop).fs_rename(temporary, path)
  if not renamed then
    vim.fn.delete(temporary)
    error("Failed to restore reviewed Neovim lock: " .. (err or "unknown error"))
  end
  local lock = package.loaded["lazy.manage.lock"]
  if lock then lock.lock, lock._loaded = {}, false end
end

local function lazy_errors()
  local errors = {}
  for name, plugin in pairs(require("lazy.core.config").plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      if task:has_errors() then errors[#errors + 1] = name .. ": " .. task:output(vim.log.levels.ERROR) end
    end
  end
  if #errors > 0 then error("Lazy sync failed:\n" .. table.concat(errors, "\n")) end
end

function M.plugins(clean)
  local lazy = require("lazy")
  local options = require("lazy.core.config").options
  options.git = options.git or {}
  options.git.timeout = 600
  local lockfile = options.lockfile
  local reviewed_lock = vim.fn.readfile(lockfile, "b")
  local function run(operation)
    local ok, err = pcall(function()
      operation():wait()
      lazy_errors()
    end)
    restore_lock(lockfile, reviewed_lock)
    if not ok then error(err, 0) end
  end
  run(function() return lazy.install({ wait = true, show = false, lockfile = true }) end)
  run(function() return lazy.restore({ wait = true, show = false }) end)
  if clean then run(function() return lazy.clean({ wait = true, show = false }) end) end
end

local function tools_installed()
  require("lazy").load({ plugins = { "mason.nvim" }, wait = true })
  if not mason.registry_current() then return false end
  local registry = require("mason-registry")
  for name, version in pairs(mason.tools()) do
    local ok, package = pcall(registry.get_package, name)
    if not ok or not package:is_installed() or package:get_installed_version() ~= version then return false end
  end
  return true
end

local function run_package_operations(operations, callback)
  if #operations == 0 then callback(); return end
  local pending, failure = #operations, nil
  for _, operation in ipairs(operations) do
    operation.run(function(success, operation_error)
      if not success then failure = failure or tostring(operation_error or (operation.name .. " failed")) end
      pending = pending - 1
      if pending == 0 then callback(failure) end
    end)
  end
end

function M.tools()
  require("lazy").load({ plugins = { "mason.nvim" }, wait = true })
  local registry = require("mason-registry")
  local done, failure = false, nil
  registry.refresh(function(success)
    if success == false then failure, done = "Mason registry refresh failed", true; return end
    local ok, err = pcall(function()
      local operations = {}
      for name, version in pairs(mason.tools()) do
        local package = registry.get_package(name)
        if not package:is_installed() or package:get_installed_version() ~= version then
          local target_package, target_version = package, version
          operations[#operations + 1] = {
            name = name,
            run = function(callback) target_package:install({ version = target_version }, callback) end,
          }
        end
      end
      for _, name in ipairs(mason.retired_platform_packages()) do
        local found, package = pcall(registry.get_package, name)
        if found and package:is_installed() and mason.platform_executable(name) then
          local target_package = package
          operations[#operations + 1] = {
            name = name,
            run = function(callback) target_package:uninstall(nil, callback) end,
          }
        end
      end
      run_package_operations(operations, function(operation_error)
        failure, done = operation_error, true
      end)
    end)
    if not ok then failure, done = tostring(err), true end
  end)

  if not vim.wait(300000, function() return done end, 100) then error("Mason tool synchronization timed out") end
  if failure then error(failure) end
  if not tools_installed() then error("Required Mason tools do not match their reviewed pins") end
end

local function installed_parsers()
  local installed = {}
  for _, name in ipairs(require("nvim-treesitter").get_installed("parsers")) do installed[name] = true end
  return installed
end

local function parsers_current(load_plugin)
  if load_plugin ~= false then require("lazy").load({ plugins = { "nvim-treesitter" }, wait = true }) end
  local installed = installed_parsers()
  local configs = require("nvim-treesitter.parsers")
  local info_dir = require("nvim-treesitter.config").get_install_dir("parser-info")
  for _, name in ipairs(parsers) do
    local expected = configs[name] and configs[name].install_info and configs[name].install_info.revision
    local actual = vim.fn.readfile(info_dir .. "/" .. name .. ".revision")[1]
    if not installed[name] or not expected or actual ~= expected then return false end
  end
  return true
end

function M.parsers(load_plugin)
  if load_plugin ~= false then require("lazy").load({ plugins = { "nvim-treesitter" }, wait = true }) end
  local treesitter = require("nvim-treesitter")
  local installed, missing = installed_parsers(), {}
  for _, name in ipairs(parsers) do
    if not installed[name] then missing[#missing + 1] = name end
  end
  if #missing > 0 then treesitter.install(missing):wait(300000) end
  treesitter.update(parsers):wait(300000)
  if not parsers_current(false) then error("Required Treesitter parsers are missing or stale after sync") end
end

local function git_result(arguments)
  return vim.system(arguments, { text = true }):wait()
end

local function plugin_current(plugin, commit)
  local uv = vim.uv or vim.loop
  if not plugin or plugin.enabled == false or not uv.fs_stat(plugin.dir) then return false end
  local head = git_result({ "git", "-C", plugin.dir, "rev-parse", "HEAD" })
  if head.code ~= 0 or vim.trim(head.stdout or "") ~= commit then return false end
  local status = git_result({ "git", "-C", plugin.dir, "status", "--porcelain", "--untracked-files=all" })
  if status.code ~= 0 then return false end
  for line in (status.stdout or ""):gmatch("[^\r\n]+") do
    if line ~= "?? doc/tags" then return false end
  end
  return true
end

function M.runtime_complete()
  local ok, complete = pcall(function()
    local config = require("lazy.core.config")
    local lock = vim.json.decode(table.concat(vim.fn.readfile(config.options.lockfile), "\n"))
    local windows, managed = vim.fn.has("win32") == 1, {}
    for name, entry in pairs(lock) do
      local platform_disabled = name == "lazy.nvim" and not windows
      if not platform_disabled then
        local plugin = config.plugins[name]
        if not plugin_current(plugin, entry.commit) then return false end
        managed[vim.fs.basename(plugin.dir)] = true
      end
    end
    for name, plugin in pairs(config.plugins) do
      local platform_disabled = name == "lazy.nvim" and not windows
      if plugin.enabled ~= false and not platform_disabled and not lock[name] then return false end
    end
    if not windows then
      for name in vim.fs.dir(config.options.root) do
        if not managed[name] then return false end
      end
    end
    if not tools_installed() or not parsers_current() then return false end
    return true
  end)
  return ok and complete == true
end

return M
