return {
  {
    "saghen/blink.cmp",
    opts = {
      completion = { list = { selection = "auto_insert" } },
      keymap = {
        ["<C-e>"] = { "cancel", "fallback" },
      },
    },
  },
}
