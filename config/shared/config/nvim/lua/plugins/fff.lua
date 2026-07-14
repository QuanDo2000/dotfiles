if vim.fn.has("win32") == 1 then
  return {}
end

return {
  {
    "dmtrKovalenko/fff.nvim",
    build = function() require("fff.download").download_or_build_binary() end,
    lazy = false,
    opts = {},
    keys = {
      { "<leader>ff", function() require("fff").find_files() end, desc = "Find Files (FFF)" },
      { "<leader>sg", function() require("fff").live_grep() end, desc = "Grep (FFF)" },
    },
  },
}
