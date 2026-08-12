local M = {}

local markers = { ".git", "lua", "flake.nix", "package.json", "pyproject.toml", "Cargo.toml", "go.mod" }

local function contains(root, path)
  root, path = vim.fs.normalize(root), vim.fs.normalize(path)
  return path == root or vim.startswith(path, root .. "/")
end

function M.get(buffer)
  buffer = buffer or 0
  local file = vim.api.nvim_buf_get_name(buffer)
  local matches = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    for _, workspace in ipairs(client.config.workspace_folders or {}) do matches[#matches + 1] = vim.uri_to_fname(workspace.uri) end
    matches[#matches + 1] = client.config.root_dir
  end
  matches = vim.tbl_filter(function(candidate) return candidate and candidate ~= "" and (file == "" or contains(candidate, file)) end, matches)
  table.sort(matches, function(a, b) return #vim.fs.normalize(a) > #vim.fs.normalize(b) end)
  if matches[1] then return vim.fs.normalize(matches[1]) end
  local start = file ~= "" and vim.fs.dirname(file) or (vim.uv or vim.loop).cwd()
  return vim.fs.root(start, markers) or (vim.uv or vim.loop).cwd()
end

function M.git(buffer)
  local start = M.get(buffer)
  return vim.fs.root(start, ".git") or start
end

return M
