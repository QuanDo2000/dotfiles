if vim.fn.has("win32") == 1 then
  return {}
end

return {
  {
    "dmtrKovalenko/fff.nvim",
    version = "v0.10.1",
    build = function() require("fff.download").download_or_build_binary() end,
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
