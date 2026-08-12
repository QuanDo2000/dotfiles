local module = assert(os.getenv("ROOT_MODULE"), "ROOT_MODULE missing")
package.path = vim.fs.dirname(vim.fs.dirname(module)) .. "/?.lua;" .. package.path
local root = dofile(module)
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/repo/.git", "p")
vim.fn.mkdir(base .. "/repo/deep", "p")
local file = base .. "/repo/deep/test.lua"
vim.fn.writefile({ "return true" }, file)
vim.cmd.edit(vim.fn.fnameescape(file))
assert(root.get() == vim.fs.normalize(base .. "/repo"), "marker root not detected")
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
  return {
    { id = 1001, stop = function() end, config = { root_dir = base .. "/other" } },
    { id = 1002, stop = function() end, config = { workspace_folders = { { uri = vim.uri_from_fname(base .. "/repo") }, { uri = vim.uri_from_fname(base .. "/repo/deep") } }, root_dir = base } },
  }
end
assert(root.get() == vim.fs.normalize(base .. "/repo/deep"), "LSP root must use most specific containing workspace")
local original_has = vim.fn.has
vim.fn.has = function(feature) return feature == "win32" and 1 or original_has(feature) end
vim.lsp.get_clients = function() return { { id = 1003, stop = function() end, config = { root_dir = base:upper() .. "/REPO" } } } end
assert(root.get():lower() == vim.fs.normalize(base .. "/repo"):lower(), "Windows LSP root containment must ignore case")
vim.fn.has = original_has
vim.lsp.get_clients = get_clients
vim.cmd.bdelete({ bang = true })
vim.fn.delete(base, "rf")
print("ROOT_OK")
