local terminal = dofile(assert(vim.env.PI_TERMINAL_MODULE))
local original_send = vim.api.nvim_chan_send
local sent, command, options, action
local buffer = vim.api.nvim_create_buf(false, true)
vim.b[buffer].terminal_job_id = 42
vim.b[buffer].snacks_terminal = { cmd = { "pi" } }
vim.bo[buffer].filetype = "snacks_terminal"

local original_root = vim.fs.root
vim.fs.root = function() return "/repo" end
_G.Snacks = {
  terminal = {
    get = function(cmd, opts)
      command, options = cmd, opts
      return {
        buf = buffer,
        show = function(self) return self end,
        focus = function(self) action = "focus"; return self end,
      }
    end,
    toggle = function(cmd, opts) action, command, options = "toggle", cmd, opts end,
    focus = function() error("Snacks.terminal.focus hides an already-focused terminal") end,
  },
  notify = { error = error, warn = error },
}
vim.api.nvim_chan_send = function(job, input)
  assert(job == 42)
  sent = input
end

terminal.toggle()
assert(action == "toggle")
assert(options.win.position == "right" and options.win.width == 80)
terminal.focus()
assert(action == "focus")

vim.cmd.vsplit()
vim.api.nvim_win_set_buf(0, buffer)
vim.cmd.wincmd("p")
local previous_window = vim.api.nvim_get_current_win()
vim.cmd.wincmd("p")
terminal.focus()
assert(vim.api.nvim_get_current_win() == previous_window)

terminal.send("linux", false)
assert(vim.deep_equal(command, { "pi" }))
assert(sent == "linux\r")
assert(options.cwd == "/repo")
assert(options.win.position == "right" and options.win.width == 80)

terminal.send("windows", true)
assert(command == "pi")
assert(sent == "windows")

vim.api.nvim_chan_send = original_send
vim.fs.root = original_root
print("PI_TERMINAL_OK")
