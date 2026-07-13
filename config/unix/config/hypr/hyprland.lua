-- Native Hyprland 0.55 Lua config.
-- See https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

hl.monitor({
    output    = "DP-2",
    mode      = "2560x1440@143.91",
    position  = "0x0",
    scale     = 1,
    transform = 1,
})

hl.monitor({
    output   = "DP-3",
    mode     = "3840x2160@120",
    position = "1440x0",
    scale    = 1.50,
})

hl.monitor({
    output   = "DP-1",
    mode     = "1920x1080@180",
    position = "4000x0",
    scale    = 1,
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "thunar"
local musicPlayer = "kew"
local anki        = "anki"
local app         = "uwsm app -- "
local mainMod     = "SUPER"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("bash $HOME/dotfiles/scripts/reload-waybar.sh")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd(app .. terminal .. " +new-window")
end)

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 6,
        border_size = 1,
        col = {
            active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout = "dwindle",
    },

    animations = {
        enabled = false,
    },

    dwindle = {
        preserve_split = true,
        force_split = 2,
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
    },

    cursor = {
        no_hardware_cursors = true,
    },

    input = {
        kb_layout = "us",
        sensitivity = -0.5,
    },
})

---------------
---- INPUT ----
---------------

hl.device({
    name = "logitech-g502-1",
    sensitivity = -1.0,
})

---------------------
---- KEYBINDINGS ----
---------------------

local function bind(keys, dispatcher, description, flags)
    flags = flags or {}
    flags.description = description
    hl.bind(keys, dispatcher, flags)
end

bind(mainMod .. " + Return", hl.dsp.exec_cmd(app .. terminal .. " +new-window"), "Open terminal")
bind(mainMod .. " + W", hl.dsp.window.close(), "Close window")
bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("uwsm stop"), "Log out")
bind(mainMod .. " + CTRL + L", hl.dsp.exec_cmd("hyprlock"), "Lock screen")
bind(mainMod .. " + E", hl.dsp.exec_cmd(app .. fileManager), "Open file manager")
bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(app .. fileManager .. " /mnt/storage/"), "Open storage")
bind(mainMod .. " + B", hl.dsp.exec_cmd(app .. "google-chrome-stable"), "Open browser")
bind(mainMod .. " + M", hl.dsp.exec_cmd(app .. terminal .. " -e " .. musicPlayer .. " all"), "Open music player")
bind(mainMod .. " + A", hl.dsp.exec_cmd(app .. anki), "Open Anki")
bind(mainMod .. " + N", hl.dsp.exec_cmd(app .. "obsidian"), "Open Obsidian")
bind(mainMod .. " + Space", hl.dsp.exec_cmd(app .. "fuzzel"), "Open app launcher")
bind(mainMod .. " + F1", hl.dsp.exec_cmd("bash $HOME/dotfiles/scripts/show-keybinds.sh"), "Show keybinds")

bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Toggle fullscreen")
bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), "Toggle maximize")
bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), "Toggle floating")
bind(mainMod .. " + P", hl.dsp.window.pseudo(), "Toggle pseudotiling")
bind(mainMod .. " + O", hl.dsp.layout("togglesplit"), "Toggle split direction")
bind(mainMod .. " + G", hl.dsp.group.toggle(), "Toggle window group")
bind(mainMod .. " + Tab", hl.dsp.group.next(), "Cycle grouped windows")

local directions = { H = "left", J = "down", K = "up", L = "right" }
for key, direction in pairs(directions) do
    bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = direction }), "Focus " .. direction)
    bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = direction }), "Swap window " .. direction)
    bind(mainMod .. " + ALT + " .. key, hl.dsp.window.move({ monitor = direction, follow = true }), "Move window to monitor " .. direction)
end

for i = 1, 10 do
    local key = i % 10
    bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), "Open workspace " .. i)
    bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), "Move window to workspace " .. i)
end

bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"), "Toggle scratchpad")
bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), "Move window to scratchpad")
bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), "Drag window", { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

bind(mainMod .. " + CTRL + R", hl.dsp.submap("resize"), "Enter resize mode")
hl.define_submap("resize", function()
    bind("Left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), "Resize left", { repeating = true })
    bind("Right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), "Resize right", { repeating = true })
    bind("Up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), "Resize up", { repeating = true })
    bind("Down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), "Resize down", { repeating = true })
    bind("Escape", hl.dsp.submap("reset"), "Exit resize mode")
end)

bind(mainMod .. " + Z", function()
    local zoom = hl.get_config("cursor.zoom_factor")
    hl.config({ cursor = { zoom_factor = zoom == 1 and 1.5 or 1 } })
end, "Toggle cursor zoom")

bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), "Volume up", { locked = true, repeating = true })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), "Volume down", { locked = true, repeating = true })
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), "Mute audio", { locked = true, repeating = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Mute microphone", { locked = true, repeating = true })
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), "Play or pause media", { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), "Previous track", { locked = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), "Next track", { locked = true })

bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]), "Copy region screenshot")
bind("SHIFT + Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" "$HOME/Downloads/screenshot-$(date +%F-%H%M%S).png"]]), "Save region screenshot")
bind("CTRL + Print", hl.dsp.exec_cmd([[grim -o "$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')" - | wl-copy]]), "Copy monitor screenshot")

bind(mainMod .. " + R", hl.dsp.exec_cmd("bash $HOME/dotfiles/scripts/reload-waybar.sh"), "Reload Waybar")

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

hl.workspace_rule({
    workspace = "1",
    monitor = "DP-3",
    default = true,
    persistent = true,
})

hl.workspace_rule({
    workspace = "2",
    monitor = "DP-1",
    persistent = true,
})

hl.workspace_rule({
    workspace = "3",
    monitor = "DP-2",
    persistent = true,
})
