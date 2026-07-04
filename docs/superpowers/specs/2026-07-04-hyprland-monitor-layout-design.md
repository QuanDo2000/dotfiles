# Hyprland Monitor Layout Design

## Goal

Configure Hyprland so the physical monitor layout is represented explicitly in `config/unix/config/hypr/hyprland.lua`.

## Runtime Monitor Mapping

- `DP-3`: Samsung Odyssey G80SD, `3840x2160`, largest monitor.
- `DP-1`: Samsung LS27DG30X, `1920x1080`, smaller Samsung monitor.
- `DP-2`: AOC AG241QG4, `2560x1440`, rotated clockwise in portrait orientation.

## Layout

Use a top-aligned layout with no negative coordinates:

```text
AOC rotated       Large Samsung       Small Samsung
DP-2              DP-3                DP-1
1440x2560         3840x2160           1920x1080
0x0               1440x0              5280x0
transform 1       transform 0         transform 0
```

## Config Changes

- Replace the stale single `HDMI-A-1` monitor entry with three explicit `hl.monitor` entries.
- Configure `DP-2` as `2560x1440@143.91`, position `0x0`, scale `1`, transform `1`.
- Configure `DP-3` as `3840x2160@120`, position `1440x0`, scale `1`.
- Configure `DP-1` as `1920x1080@180`, position `5280x0`, scale `1`.
- Move the default workspace monitor from `HDMI-A-1` to `DP-3`.

## Verification

- Run `Hyprland --verify-config --config config/unix/config/hypr/hyprland.lua`.
- Optionally reload Hyprland and confirm `hyprctl monitors` reports the expected positions and transforms.
