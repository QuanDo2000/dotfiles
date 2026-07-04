# Near-zero-touch NixOS provisioning

**Date:** 2026-07-03
**Status:** Approved, ready for implementation plan
**Builds on:** 2026-07-03-nixos-support-design.md (the preliminary NixOS layer)

## Goal

Make provisioning a fresh NixOS machine as close to one command as possible.
Today the tracked `configuration.nix` requires the user to copy in
`hardware-configuration.nix`, hand-edit per-machine knobs (hostname, username,
timezone, stateVersion), and reconcile a channel mismatch (ghostty/opencode not
in 24.11 stable). This eliminates all of that: values are auto-detected from the
freshly-installed system, confirmed once interactively, and channel-sensitive
packages are guarded so a rebuild can't eval-fail.

End state for a fresh install:

```
nix-shell -p git --run 'git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles && cd ~/dotfiles && sudo bash ./dotfile packages'
```

## Decisions

- **Detect, then confirm** (chosen over silent auto-apply and over a
  manual-edit-only pass). First run detects values and lets the user accept or
  override each before writing them.
- **Inline in `dotfile packages`/`all`, first run only** (chosen over a separate
  `dotfile nixos` subcommand). If `/etc/nixos/machine.nix` is missing, the
  packages flow detects+confirms+writes it, then rebuilds. Re-runs are silent.
- **`machine.nix` at `/etc/nixos/machine.nix`**, imported by absolute path. Same
  reasoning as the hardware config: `configuration.nix` is symlinked into
  `/etc/nixos`, and Nix resolves relative imports against the symlink *target*
  (the repo dir), so relative imports would look in the wrong place. Absolute
  `/etc/nixos/...` paths are symlink-safe.
- **Channel-safe packages** via `lib.optional (pkgs ? ghostty)` — install
  ghostty/opencode only if the running channel actually provides them. No human
  channel decision, no failed rebuild.

## Design

### 1. `configuration.nix` restructure

The tracked config stops hardcoding per-machine values; it reads them from
`/etc/nixos/machine.nix` and imports the hardware config by absolute path:

```nix
{ config, pkgs, lib, ... }:
let
  machine = import /etc/nixos/machine.nix;
in {
  imports = [ /etc/nixos/hardware-configuration.nix ];

  system.stateVersion = machine.stateVersion;
  networking.hostName = machine.hostName;
  time.timeZone       = machine.timeZone;
  # ... nix flakes feature, locale, boot, greetd, hyprland, fcitx5, fonts
  #     (unchanged from the preliminary layer) ...

  programs.zsh.enable = true;
  users.users.${machine.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
  };

  environment.systemPackages =
    (with pkgs; [ git zsh tmux neovim fzf fd ripgrep lazygit jujutsu starship
                  zoxide gnupg wl-clipboard openssh unzip fontconfig
                  tree-sitter lua5_1 luarocks waybar ])
    ++ lib.optional (pkgs ? ghostty) pkgs.ghostty
    ++ lib.optional (pkgs ? opencode) pkgs.opencode;
}
```

Consequences:
- The `# EDIT:` per-machine markers and the ghostty/opencode channel `NOTE`
  comment are removed — those concerns are now auto-derived / channel-guarded.
  The Hyprland-services `# EDIT:` stub (pipewire/graphics/xdg-portal) stays: it
  is a genuine hardware/taste choice, not something to auto-detect.
- `hardware-configuration.nix` no longer belongs in the repo. Its `.gitignore`
  entry (`config/nixos/hardware-configuration.nix`) is removed.
- `lib` is added to the module's argument set for `lib.optional`.

### 2. `machine.nix` — machine-local values

Generated once at `/etc/nixos/machine.nix` (root-owned, outside the repo):

```nix
{
  username = "quan";
  hostName = "nixos";
  timeZone = "Asia/Ho_Chi_Minh";
  stateVersion = "24.11";
}
```

Detection sources (all populated by the NixOS installer on a fresh box), each
with a fallback so detection never hard-fails:

| Field | Source | Fallback |
|-------|--------|----------|
| `username` | `${SUDO_USER:-$(whoami)}` | `$(whoami)` |
| `hostName` | `hostname` | `nixos` |
| `timeZone` | `timedatectl show -p Timezone --value` | `UTC` |
| `stateVersion` | `nixos-version`, first two dot-components (e.g. `24.11`) | `24.11` |

### 3. Flow

A shared helper `_nixos_ensure_linked`:

1. If `/etc/nixos/machine.nix` is missing (or `FORCE`):
   - detect the four values;
   - if a TTY is attached and not `DRY`, prompt per field — print
     `  <label> [<detected>]: `, read a line, empty input keeps the detected
     value;
   - write the attrset via `sudo tee /etc/nixos/machine.nix`.
2. `sudo ln -sfn "$DOTFILES_DIR/config/nixos/configuration.nix"
   /etc/nixos/configuration.nix` (leaves `/etc/nixos/hardware-configuration.nix`
   untouched).

`install_nixos` = `_nixos_ensure_linked` then `sudo nixos-rebuild switch`.
`update_nixos` = `_nixos_ensure_linked` then `sudo nixos-rebuild switch --upgrade`.

Both are self-sufficient and idempotent, so ordering doesn't matter and there is
no wasted rebuild of the stock installer config. Re-runs find `machine.nix`
present and proceed silently — true zero-touch after the first run. `-f`/`FORCE`
regenerates `machine.nix`.

Non-interactive contexts (no TTY — tests, CI, piped input) or `DRY` skip the
prompt and use the detected values. Guard: prompt only when
`[[ -t 0 && "$DRY" == "false" ]]`.

*Note:* `dotfile packages` runs `update_packages` then `install_packages`, so on
NixOS it rebuilds twice (`--upgrade` then plain). The second is a near-instant
no-op because nothing changed between them. Not worth deduping.

### 4. Units and testability

Split so the write path is pure and testable off a non-NixOS host:

- `_write_nixos_machine_file <path> <username> <hostName> <timeZone> <stateVersion>`
  — pure: writes the Nix attrset to `<path>`. Tested directly by asserting the
  file contents (valid attrset, correct values). The machine-file path is
  overridable via `NIXOS_MACHINE_FILE` (default `/etc/nixos/machine.nix`) so
  tests write to a temp path.
- `_detect_nixos_machine_values` — echoes the four detected values. Smoke-tested
  with `hostname`/`timedatectl`/`nixos-version` mocked via the helpers'
  function-override mechanism (like `mock_uname`), since the test host is not
  NixOS.
- `_nixos_ensure_linked` — orchestration: skip-when-`machine.nix`-exists, `DRY`
  makes no writes, non-TTY doesn't block on a prompt.

### 5. README

Add a "Provisioning a fresh NixOS machine" section with the one-liner from the
Goal, plus one line each on: values are auto-detected and confirmed on first
run; `hardware-configuration.nix` is used in place from `/etc/nixos`; re-running
is silent.

## Testing

- `test_packages.sh`: `_write_nixos_machine_file` content; `_nixos_ensure_linked`
  skip-when-exists and `DRY` no-write behavior (using `NIXOS_MACHINE_FILE` +
  `DOTFILES_DIR` temp paths); `_detect_nixos_machine_values` with mocked system
  commands.
- Existing NixOS tests (`install_nixos`/`update_nixos` DRY, dispatch, zsh guard)
  continue to pass unchanged.
- Full suite green (`bash tests/bash/runner.sh --no-docker`).

## Out of scope

- Auto-detecting or auto-enabling desktop hardware services (pipewire, GPU,
  xdg-portal) — left as the `# EDIT:` stub; genuine per-machine choices.
- Flakes, home-manager, porting app configs into Nix (still deferred from the
  base layer).
- Partitioning/installing NixOS itself — the machine is assumed already
  installed (so `/etc/nixos/hardware-configuration.nix` exists).

## Docs to update

- `CLAUDE.md` NixOS layer entry: values now come from auto-detected
  `/etc/nixos/machine.nix`; `hardware-configuration.nix` used in place; no
  hand-editing on first run.
- `README.md`: the new provisioning section.
