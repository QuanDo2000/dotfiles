# Hyprland Lua Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Hyprland 0.55 `hyprland.lua` config that preserves the current `hyprland.conf` behavior.

**Architecture:** Keep one Lua config file under the existing `config/unix/config/hypr/` directory so the current dotfile symlink flow continues to work unchanged. Use Hyprland's native `hl.*` API directly, with tiny Lua loops only for repeated workspace bindings.

**Tech Stack:** Hyprland 0.55 Lua config API, Lua, existing bash test runner.

## Global Constraints

- Add `config/unix/config/hypr/hyprland.lua`.
- Preserve current `hyprland.conf` behavior for monitor setup, programs, autostart, environment variables, look and feel, input, binds, window rules, and workspace rules.
- Leave `hypridle.conf` and `hyprlock.conf` unchanged.
- Do not change the dotfile symlink flow.
- No module split, generator, compatibility wrapper, or new dependency.
- Mark intentional simplifications with a `ponytail:` comment when a simplification is non-obvious.

---

## File Structure

- Create: `config/unix/config/hypr/hyprland.lua`
  - Responsibility: native Hyprland Lua compositor config replacing the legacy `hyprland.conf` at Hyprland startup.
- Read-only reference: `config/unix/config/hypr/hyprland.conf`
  - Responsibility: source behavior to port; leave it in place as rollback/reference.
- No changes: `config/unix/config/hypr/hypridle.conf`
- No changes: `config/unix/config/hypr/hyprlock.conf`
- No changes: `scripts/symlinks.sh`

---

### Task 1: Add Hyprland Lua Config

**Files:**
- Create: `config/unix/config/hypr/hyprland.lua`
- Reference: `config/unix/config/hypr/hyprland.conf`

**Interfaces:**
- Consumes: Hyprland's global Lua `hl` API.
- Produces: `config/unix/config/hypr/hyprland.lua`, loaded by Hyprland 0.55 when symlinked to `~/.config/hypr/hyprland.lua`.

- [ ] **Step 1: Create the Lua config with preserved behavior**

Use this complete file content for `config/unix/config/hypr/hyprland.lua`:

```lua
-- Native Hyprland 0.55 Lua config.
-- See https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "dolphin"
local menu        = "vicinae toggle"
local musicPlayer = "kew"
local anki        = "anki"
local mainMod     = "SUPER"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("waybar & dunst & hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("copyq --start-server")
    hl.exec_cmd("vicinae server")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("[workspace 1 silent] " .. terminal .. " +new-window")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border = false,
        allow_tearing = true,
        layout = "dwindle",
    },

    decoration = {
        active_opacity = 1.0,
        inactive_opacity = 1.0,
    },

    animations = {
        enabled = false,
    },

    dwindle = {
        preserve_split = true,
        force_split = 2,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
    },

    xwayland = {
        force_zero_scaling = 0,
    },

    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = -0.5,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.layer_rule({
    name = "blur-vicinae",
    match = { namespace = "vicinae" },
    blur = true,
})

hl.layer_rule({
    name = "ignorealpha-vicinae",
    match = { namespace = "vicinae" },
    ignore_alpha = 0,
})

---------------
---- INPUT ----
---------------

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.device({
    name = "logitech-g502",
    sensitivity = -1.0,
})

---------------------
---- KEYBINDINGS ----
---------------------

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal .. " +new-window"))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(fileManager .. " /mnt/storage/"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("google-chrome-stable"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(terminal .. " -e " .. musicPlayer .. " all"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(anki))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + O", hl.dsp.layout("togglesplit"))
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region"))

hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- ponytail: loop only the repetitive workspace number binds; one-off binds stay explicit.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("pkill waybar && waybar &"))

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
    monitor = "HDMI-A-1",
    default = true,
})
```

- [ ] **Step 2: Verify syntax with Lua if available**

Run:

```bash
command -v lua >/dev/null 2>&1 && lua -e 'assert(loadfile("config/unix/config/hypr/hyprland.lua"))' || true
```

Expected:

- If `lua` is installed, no output and exit 0.
- If `lua` is not installed, command exits 0 because syntax validation is unavailable locally.

- [ ] **Step 3: Verify Lua parser fallback with bytecode check if `lua -p` is unavailable**

Run:

```bash
command -v luac >/dev/null 2>&1 && luac -p config/unix/config/hypr/hyprland.lua || true
```

Expected:

- If `luac` is installed, no output and exit 0.
- If `luac` is not installed, command exits 0 because syntax validation is unavailable locally.

- [ ] **Step 4: Verify no symlink test regression**

Run:

```bash
bash tests/bash/runner.sh --no-docker test_symlinks.sh test_platform.sh
```

Expected: all listed tests pass; the final summary reports `0 failed`.

- [ ] **Step 5: Review changed files**

Run:

```bash
git diff -- config/unix/config/hypr/hyprland.lua
```

Expected: diff shows only the new Lua config file and no changes to `hypridle.conf`, `hyprlock.conf`, or symlink scripts.

---

## Self-Review

- Spec coverage: Task 1 adds `hyprland.lua`, preserves compositor behavior, leaves Hypridle/Hyprlock unchanged, and does not alter symlink flow.
- Placeholder scan: no TBD/TODO/fill-in-later placeholders remain.
- Type/API consistency: the plan uses the `hl.*` API shape shown in Hyprland's upstream example `hyprland.lua`.
