-- Run through `dotfile rex-work`: the CLI and this checkout are on the same host.
local project = os.getenv("DOTFILES_DIR")
assert(project and project:sub(1, 1) == "/", "DOTFILES_DIR must be an absolute checkout path")

for _, session in ipairs(rex.call("session.list").sessions or {}) do
  if session.label == "dotfiles" then
    error("dotfiles session already exists: " .. session.session_id
      .. "; select it in Rex, or rename it before creating another workspace")
  end
end

-- One native transaction: no half-created session if a layout fails to start.
-- No initial_input: the checks pane is a shell, not an automatic test run.
return rex.call("session.create", {
  label = "dotfiles",
  initial_windows = {{
    window_label = "Workspace",
    layout = {
      split = {
        direction = "horizontal",
        ratio = 0.6,
        before = { block = {
          flavor = "com.superlogical.terminal.shell",
          label = "Editor",
          options = { cwd = project, shell = "zsh", command = { "nvim", "." } },
        } },
        after = { split = {
          direction = "vertical",
          ratio = 0.5,
          before = { block = {
            flavor = "com.superlogical.terminal.shell",
            label = "Shell",
            options = { cwd = project, shell = "zsh" },
          } },
          after = { block = {
            flavor = "com.superlogical.terminal.shell",
            label = "Checks",
            options = { cwd = project, shell = "zsh" },
          } },
        } },
      },
    },
  }},
})
