local terminal = require("config.pi-terminal")

return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
      { "<c-.>", terminal.focus, desc = "Focus Pi", mode = { "n", "t", "i", "x" } },
      { "<leader>aa", terminal.toggle, desc = "Toggle Pi" },
      { "<leader>at", terminal.send_position, desc = "Send Position", mode = { "n", "x" } },
      { "<leader>af", terminal.send_file, desc = "Send File" },
      { "<leader>av", terminal.send_selection, desc = "Send Selection", mode = "x" },
    },
  },
}
