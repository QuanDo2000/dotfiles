if vim.fn.has("win32") == 1 then
  return {}
end

return {
  {
    "dmtrKovalenko/fff.nvim",
    version = "v0.10.1",
    build = function(plugin)
      local uv = vim.uv or vim.loop
      local source = vim.fn.stdpath("config") .. "/fff-nvim-backend"
      local extension = vim.fn.has("mac") == 1 and "dylib" or "so"
      local target = plugin.dir .. "/target/release/libfff_nvim." .. extension
      local stat = uv.fs_stat(source)
      if not stat or stat.type ~= "file" then error("Nix-managed fff.nvim backend is missing: " .. source) end
      vim.fn.mkdir(vim.fs.dirname(target), "p")
      vim.fn.delete(target)
      local ok, err = uv.fs_symlink(source, target)
      if not ok then error("Failed to link fff.nvim backend: " .. (err or "unknown error")) end
    end,
    lazy = false,
    opts = {
      frecency = { db_path = vim.env.FFF_FRECENCY_DB or vim.fn.expand("~/.local/state/fff/frecency") },
      history = { db_path = vim.env.FFF_HISTORY_DB or vim.fn.expand("~/.local/state/fff/history") },
    },
    keys = {
      { "<leader>ff", function() require("fff").find_files() end, desc = "Find Files (FFF)" },
      { "<leader>sg", function() require("fff").live_grep() end, desc = "Grep (FFF)" },
    },
  },
}
