return {
  {
    "dmtrKovalenko/fff.nvim",
    lazy = false,
    opts = {},
    keys = {
      { "<leader>ff", function() require("fff").find_files() end, desc = "Find Files (FFF)" },
      { "<leader>sg", function() require("fff").live_grep() end, desc = "Grep (FFF)" },
    },
  },
}
