local function keep_pi_input_unsubmitted(backend)
  if backend._pi_no_submit then return end
  backend._pi_no_submit = true
  local send = backend.send
  backend.send = function(self, input)
    if self.tool and self.tool.name == "pi" and input:sub(-1) == "\n" then
      input = input:sub(1, -2)
    end
    return send(self, input)
  end
end

return {
  {
    "folke/sidekick.nvim",
    opts = {
      nes = { enabled = false },
    },
    config = function(_, opts)
      require("sidekick").setup(opts)
      if vim.fn.has("win32") == 1 then
        keep_pi_input_unsubmitted(require("sidekick.cli.terminal"))
      end
    end,
  },
}
