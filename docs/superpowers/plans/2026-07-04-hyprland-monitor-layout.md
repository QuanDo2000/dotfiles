# Hyprland Monitor Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Hyprland so the AOC portrait monitor is on the left, the largest Samsung monitor is centered, and the smaller Samsung monitor is on the right.

**Architecture:** This is a direct Hyprland Lua configuration change. The monitor layout is represented by explicit `hl.monitor` entries, and the default workspace rule points to the centered primary display.

**Tech Stack:** Hyprland 0.55 Lua config, bash verification commands.

## Global Constraints

- Modify only `config/unix/config/hypr/hyprland.lua` for runtime behavior.
- Preserve the existing Lua config style and avoid helper abstractions.
- Use the approved top-aligned layout with no negative coordinates.
- Do not change unrelated Hyprland settings.

---

### Task 1: Configure Explicit Monitor Layout

**Files:**
- Modify: `config/unix/config/hypr/hyprland.lua:8-13`
- Modify: `config/unix/config/hypr/hyprland.lua:211-215`

**Interfaces:**
- Consumes: Runtime output names from `hyprctl monitors`: `DP-2`, `DP-3`, `DP-1`.
- Produces: Hyprland Lua config with three explicit `hl.monitor` entries and default workspace monitor `DP-3`.

- [ ] **Step 1: Confirm current stale monitor config**

Read `config/unix/config/hypr/hyprland.lua` and confirm the monitor section currently contains only:

```lua
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})
```

Expected: the old single `HDMI-A-1` entry is present.

- [ ] **Step 2: Replace the monitor section**

Replace the old `hl.monitor` block with:

```lua
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
    scale    = 1,
})

hl.monitor({
    output   = "DP-1",
    mode     = "1920x1080@180",
    position = "5280x0",
    scale    = 1,
})
```

- [ ] **Step 3: Move default workspace rule to the centered monitor**

Change the existing workspace rule from:

```lua
hl.workspace_rule({
    workspace = "1",
    monitor = "HDMI-A-1",
    default = true,
})
```

to:

```lua
hl.workspace_rule({
    workspace = "1",
    monitor = "DP-3",
    default = true,
})
```

- [ ] **Step 4: Verify Hyprland accepts the Lua config**

Run: `Hyprland --verify-config --config config/unix/config/hypr/hyprland.lua`

Expected: output includes `config ok` and exits 0.

- [ ] **Step 5: Optionally reload and inspect runtime geometry**

Run: `hyprctl reload`

Expected: exits 0.

Run: `hyprctl monitors`

Expected: reports these effective positions and transform:

```text
DP-2 at 0x0, transform: 1
DP-3 at 1440x0, transform: 0
DP-1 at 5280x0, transform: 0
```

## Self-Review

- Spec coverage: The plan updates all monitor entries, preserves top alignment, rotates the AOC clockwise, and moves the default workspace to `DP-3`.
- Placeholder scan: No placeholders remain.
- Type consistency: Monitor output names, positions, refresh rates, and transform values match the design spec.
