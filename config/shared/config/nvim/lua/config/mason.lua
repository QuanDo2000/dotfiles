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

return M
