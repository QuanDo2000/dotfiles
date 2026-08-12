local M = {}

local function is_windows(value)
  return value == nil and vim.fn.has("win32") == 1 or value == true
end

local function command(windows)
  return is_windows(windows) and "pi" or { "pi" }
end

local function options()
  return {
    cwd = LazyVim.root(),
    win = { position = "right", width = 80 },
  }
end

local function current_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return end
  return "@" .. (vim.fs.relpath(LazyVim.root(), file) or file)
end

local function terminal(windows)
  return Snacks.terminal.get(command(windows), options())
end

function M.toggle()
  Snacks.terminal.toggle(command(), options())
end

function M.focus()
  local current = vim.b.snacks_terminal
  if vim.bo.filetype == "snacks_terminal" and current and current.cmd then
    local cmd = current.cmd
    if cmd == "pi" or type(cmd) == "table" and cmd[1] == "pi" then
      vim.cmd.wincmd("p")
      vim.cmd.stopinsert()
      return
    end
  end
  terminal():show():focus()
end

function M.send(text, windows)
  if not text or text == "" then
    Snacks.notify.warn("Nothing to send")
    return
  end

  local window = terminal(windows)
  window:show():focus()
  local job = vim.b[window.buf].terminal_job_id
  if not job then
    Snacks.notify.error("Pi terminal is not ready")
    return
  end
  vim.api.nvim_chan_send(job, text .. (is_windows(windows) and "" or "\r"))
end

function M.send_file()
  M.send(current_file())
end

function M.send_position()
  local file = current_file()
  if not file then return M.send() end

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local from, to = vim.fn.getpos("v"), vim.fn.getpos(".")
    if from[2] > to[2] or (from[2] == to[2] and from[3] > to[3]) then from, to = to, from end
    if mode == "V" then
      M.send(("%s :L%d-L%d"):format(file, from[2], to[2]))
    else
      M.send(("%s :L%d:C%d-L%d:C%d"):format(file, from[2], from[3], to[2], to[3]))
    end
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  M.send(("%s :L%d:C%d"):format(file, cursor[1], cursor[2] + 1))
end

function M.send_selection()
  local mode = vim.fn.mode()
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  M.send(table.concat(lines, "\n"))
end

return M
