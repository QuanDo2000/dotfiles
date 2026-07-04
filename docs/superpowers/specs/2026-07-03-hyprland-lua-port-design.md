# Hyprland Lua Port Design

## Goal

Port the current Hyprland compositor config from Hyprlang to Hyprland 0.55's native Lua config format while preserving behavior.

## Scope

- Add `config/unix/config/hypr/hyprland.lua`.
- Preserve the current `hyprland.conf` behavior for monitor setup, programs, autostart, environment variables, look and feel, input, binds, window rules, and workspace rules.
- Leave `hypridle.conf` and `hyprlock.conf` unchanged because Hyprland's Lua announcement says Hypr* tools continue using Hyprlang for now, and the tools are not installed locally to verify Lua support.
- Keep the existing dotfile symlink flow unchanged because `setup_symlinks_folder` already links the whole `hypr` config directory.

## Approach

Use one native `hyprland.lua` file with Hyprland's `hl.*` Lua API. Avoid a module split, generator, or compatibility wrapper until the config grows enough to justify it.

`hyprland.lua` will keep explicit statements for one-off settings and use small Lua loops only where the existing config repeats the same pattern, such as workspace binds from 1 through 10.

## Behavior Mapping

- `monitor = HDMI-A-1, 1920x1080@60, 0x0, 1` becomes `hl.monitor` with matching output, mode, position, and scale.
- `$terminal`, `$fileManager`, `$menu`, `$musicPlayer`, and `$anki` become Lua locals.
- `exec-once` entries become `hl.on("hyprland.start", function() ... end)` plus `hl.exec_cmd(...)` calls.
- `env` entries become `hl.env(...)` calls.
- `general`, `decoration`, `animations`, `dwindle`, `master`, `misc`, `xwayland`, and `input` become `hl.config(...)` tables.
- `gesture`, `device`, `layerrule`, `bind`, `bindm`, `bindl`, `bindel`, `windowrule`, and `workspace` entries become the corresponding `hl.*` or dispatcher calls from the upstream example API.
- Removed or obsolete Hyprland 0.55 options should be omitted rather than emulated.

## Validation

- Check Lua syntax with the local Lua interpreter if available.
- Check Hyprland config loading with a non-destructive Hyprland/`hyprctl` command if one exists locally.
- Run relevant bash tests if symlink behavior changes; no symlink behavior change is expected.

## Intentional Simplifications

- No module split yet. The current config is small enough for one file.
- No generated compatibility file. Hyprland 0.55 prefers `hyprland.lua` when present, and `hyprland.conf` remains available as a human rollback reference.
- No port of `hypridle.conf` or `hyprlock.conf` until those tools' Lua support is verified.
