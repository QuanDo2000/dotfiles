local M = {}

local tools = {
  "json-lsp",
  "lua-language-server",
  "markdownlint-cli2",
  "marksman",
  "prettier",
  "stylua",
  "taplo",
  "yaml-language-server",
}

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

  local fff = require("lazy.core.config").plugins["fff.nvim"]
  if fff and fff.enabled ~= false then
    M.link_fff(fff)
    require("fff")
  end
end

local function tools_installed()
  require("lazy").load({ plugins = { "mason.nvim" }, wait = true })
  local registry = require("mason-registry")
  for _, name in ipairs(tools) do
    local ok, package = pcall(registry.get_package, name)
    if not ok or not package:is_installed() then return false end
  end
  return true
end

function M.tools()
  if tools_installed() then return end
  local registry = require("mason-registry")
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
  if not tools_installed() then error("Required Mason tools are missing after sync") end
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
      local platform_disabled = (name == "lazy.nvim" and not windows) or (name == "fff.nvim" and windows)
      if not platform_disabled then
        local plugin = config.plugins[name]
        if not plugin_current(plugin, entry.commit) then return false end
        managed[vim.fs.basename(plugin.dir)] = true
      end
    end
    for name, plugin in pairs(config.plugins) do
      local platform_disabled = (name == "lazy.nvim" and not windows) or (name == "fff.nvim" and windows)
      if plugin.enabled ~= false and not platform_disabled and not lock[name] then return false end
    end
    if not windows then
      for name in vim.fs.dir(config.options.root) do
        if not managed[name] then return false end
      end
    end
    if not tools_installed() or not parsers_current() then return false end

    if not windows then
      local uv = vim.uv or vim.loop
      local fff = config.plugins["fff.nvim"]
      local source = vim.fn.stdpath("config") .. "/fff-nvim-backend"
      local target = fff and (fff.dir .. "/target/release/libfff_nvim." .. (vim.fn.has("mac") == 1 and "dylib" or "so"))
      if not target or not uv.fs_stat(source) or uv.fs_realpath(source) ~= uv.fs_realpath(target) then return false end
      require("fff")
    end
    return true
  end)
  return ok and complete == true
end

return M
