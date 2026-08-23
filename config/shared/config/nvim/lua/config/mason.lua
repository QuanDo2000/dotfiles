local M = {}

local function pins()
  local path = vim.fn.stdpath("config") .. "/mason-tools.json"
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

function M.registry()
  return "github:mason-org/mason-registry@" .. pins().registryVersion
end

function M.tools()
  return pins().tools
end

function M.retired_platform_packages()
  return pins().retiredPlatformPackages
end

function M.registry_current()
  local path =
    vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "registries", "github", "mason-org", "mason-registry", "info.json")
  local ok, info = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  local expected = pins()
  return ok
    and info.version == expected.registryVersion
    and info.checksums
    and info.checksums["registry.json.zip"] == expected.registrySha256
end

function M.platform_executable(name)
  local mason_bin = vim.fs.normalize(vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin"))
  local separator = vim.fn.has("win32") == 1 and ";" or ":"
  local original = vim.env.PATH
  local paths = vim.tbl_filter(function(path)
    return vim.fs.normalize(path) ~= mason_bin
  end, vim.split(original, separator, { plain = true }))
  vim.env.PATH = table.concat(paths, separator)
  local ok, executable = pcall(vim.fn.executable, name)
  vim.env.PATH = original
  return ok and executable == 1
end

return M
