return {
  {
    "saghen/blink.cmp",
    opts = {
      completion = { list = { selection = { auto_insert = true } } },
      keymap = {
        ["<C-e>"] = { "cancel", "fallback" },
      },
    },
  },
}
