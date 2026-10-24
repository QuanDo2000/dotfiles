-- Keep Rex's native Cmd shortcuts; add the existing tmux Ctrl+B vocabulary.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>ctrl+p", "client.tab.previous")
rex.bind("ctrl+b>ctrl+n", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
rex.bind("ctrl+b>n", "client.tab.next")
rex.bind("ctrl+b>shift+,", "client.tab.move", { direction = "backward" })
rex.bind("ctrl+b>shift+.", "client.tab.move", { direction = "forward" })
rex.bind("ctrl+b>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+b>shift+5", "pane.split", { direction = "right" })
rex.bind("ctrl+b>-", "pane.split", { direction = "down" })
rex.bind("ctrl+b>shift+'", "pane.split", { direction = "down" })
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("ctrl+b>s", "session.switch")
rex.bind("ctrl+b>shift+r", "client.config.reload")

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+b>" .. key, "pane.focus", { direction = direction })
  rex.bind("ctrl+b>ctrl+" .. key, "pane.focus", { direction = direction })
  -- Rex measures resize steps as percentages, not tmux's cells.
  rex.bind("ctrl+b>shift+" .. key, "pane.resize", { direction = direction, amount = 5 })
end
for index = 1, 9 do
  rex.bind("ctrl+b>" .. index, "client.tab.goto", { index = index })
end

-- Explicit reapply; activation/first Rex shell imports and selects it once.
rex.bind("ctrl+b>shift+t", "client.theme.import", {
  path = os.getenv("HOME") .. "/.config/rex/Catppuccin Macchiato.conf",
})
