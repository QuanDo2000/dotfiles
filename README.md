# dotfiles

Personal setup scripts and configuration files for new machines.

## Requirements

### Linux / macOS

- `sudo`, `curl`, and `git`

### Windows

- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7 (`pwsh`)
- Must be run from an **Administrator** PowerShell (required to create symlinks).
  The script self-elevates via `Start-Process -Verb RunAs` if needed.
- `git` (install via `winget install Git.Git` first, or use another existing Git installation)
- The script installs `winget` packages and the pinned FiraCode Nerd Font; no extra package manager required.

### Configuration

- `DOTFILES_DIR` environment variable may be set to override where the repo is
  expected to live. Defaults:
  - Linux/macOS: `$HOME/dotfiles`
  - Windows: the parent of the `dotfile.ps1` script location.

## Usage

### Linux / macOS

First-time setup:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/dotfile
```

After Home Manager applies, the `dotfile` command is available in your PATH:

```bash
dotfile
```

### Linux with Nix/Home Manager

Arch and Debian use the native package manager only for bootstrap packages,
then use this repo's pinned flake to install Home Manager user tools and config:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/dotfile all
```

Generic Linux and Debian use `${username}@linux`; Arch uses
`${username}@arch-server`. `username` comes from `config/host.nix`.
`dotfile packages` installs Lix/Nix if missing, uses
an existing `home-manager` when available, and falls back to the pinned
`~/dotfiles#home-manager` app for bootstrap. Lix installer and package artifacts
are used only after their tracked SHA-256 matches; review changes from
`dotfile lix-installer` before committing updated installer pins.

#### Activate an existing Arch server setup from Bash

For the Arch-server role only (Obsidian Sync, Google Drive, and storage backup,
not a generic Linux or desktop profile), with native prerequisites, Nix, and the
repo's guarded `home-manager` already installed: run this only from an external
user terminal after approval. Adjust the checkout path if needed.

```bash
/usr/bin/bash --noprofile --norc -euo pipefail -c '
  export DOTFILES_DIR="$HOME/dotfiles"
  export DOTFILE_FLAKE_REF="path:$DOTFILES_DIR"
  export DRY=false QUIET=false FORCE=false
  source "$DOTFILES_DIR/scripts/utils.sh"
  source "$DOTFILES_DIR/scripts/platform.sh"
  source "$DOTFILES_DIR/scripts/packages.sh"
  _home_manager_switch arch-server
'
```

Use this standalone native Bash invocation even from zsh: the helpers use a
local `status` variable, which is read-only in zsh. `packages.sh` loads
`host_config.sh`; `host_config_value username` reads `config/host.nix` (falling
back to `nix eval` if needed), not the login username. The current value is
`quando`, so the target is `path:<checkout>#quando@arch-server`.

This activates the existing pins, rather than refreshing pins with `dotfile
update` or bootstrapping packages with `dotfile packages`. The `path:` reference
includes current local checkout content, including uncommitted changes; it does
not guarantee an unchanged package closure. Activation can change packages,
configuration, and user services.

Keep the installed `home-manager` profile guard on PATH and never bypass it or
remove its initialization markers: `config/home.nix` rejects switches away from
`arch-server` when Google Drive or storage initialization markers exist. Stop
and investigate any refusal. A helper preview with `DRY=true` only prints the
target command; it does not exercise the installed profile guard or activation.

### Windows

Run the following in PowerShell as Administrator:

```powershell
git clone https://github.com/QuanDo2000/dotfiles.git $HOME\Documents\Projects\dotfiles
& $HOME\Documents\Projects\dotfiles\dotfile.ps1
```

### Unix Commands

```bash
dotfile [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Refresh all managed dependency pins and validate
              Install native prerequisites and activate current profile
              Update only AI tools and configs with `update ai`
  packages    Install system packages only
  upgrade     Upgrade native system packages
  obsidian    Bootstrap Obsidian Sync login and vault setup
  codex       Update pinned Codex release package
  lix-installer
              Update pinned Lix installer checksums
  obsidian-headless
              Update pinned Obsidian Headless package
  doctor [--fast]
              Detect dotfile and Nix issues
  check       Run full repository checks

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

`dotfile upgrade` runs `sudo pacman -Syu` on Arch, `sudo apt-get update` plus
`sudo apt-get upgrade -y` on Debian, or `brew update` plus `brew upgrade --greedy` on
macOS. NixOS remains declarative; use `dotfile update` there.

### Windows Commands

```powershell
dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Update system packages
              Update only AI tools and configs with `update ai`
  packages    Install all managed packages only
  ai          Install AI tools and shared skills
  doctor      Detect Windows installation issues
  verify      Verify installation

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files without prompting
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

Windows `all`, `packages`, and full `update` manage Anki and Obsidian through
WinGet. Close both apps before running these commands.

AnkiConnect, Pass/Fail 2, and Zoom are pinned in `config/windows/anki-addons.json`.
Downloads are SHA-256 checked. Anki's automatic updates are disabled for these
add-ons so it cannot replace the pinned code. `dotfile doctor` checks installed
pin markers, individual distribution file hashes, enabled/update flags, and
managed settings. It reports drift without changing anything.

Refresh the Anki pins without installing them:

```powershell
py -3.14 scripts/update_pins.py anki-addons .
git diff -- config/windows/anki-addons.json
```

The refresher downloads each archive twice, validates paths and the entry point,
and writes pins only after all archives pass. Review changes before installation;
matching downloads are not a security audit of new add-on code. The Unix full
pin-refresh workflow also refreshes these Windows pins.

Managed settings use the existing Windows preferences captured in
`config/windows/anki-addons.json`, including Zoom's custom zoom levels, rather
than the Unix defaults. Other settings and `user_files` are preserved; decks, profiles, and
unrelated add-ons are untouched. Previous managed add-on directories are retained
under `%APPDATA%\Anki2\dotfile-addons-backups`. Only the default
`%APPDATA%\Anki2\addons21` location is managed. AnkiConnect stays bound to
`127.0.0.1:8765` with a localhost-only CORS allowlist. Existing API keys remain
local and are preserved; they are never included in the tracked configuration.

Obsidian uses its single registered vault. If there are multiple vaults, set
`DOTFILE_OBSIDIAN_VAULT` to the existing vault's absolute path. With no registered
vault, open/create the intended vault in Obsidian once, close the app, then retry.
Dotfile never starts vault synchronization or chooses among multiple vaults.

Only the selected top-level settings and plugin `data.json` files are copied as
writable files. Existing Windows preferences were captured: matching files reuse
`config/shared/obsidian/`, while differences live in `config/windows/obsidian/`.
Notes, workspaces, login credentials, Sync state, and unlisted settings are left
alone. Changed files get a sibling `.backup.<id>` copy. Plugin binaries and themes
remain managed through Obsidian; on a new vault, install the desired plugins and
theme there before using their settings. `update ai` does not touch either app.

Note: Unix dotfiles are managed by Home Manager. `~/.zshrc` is generated from `config/unix/.zshrc.base`.

Run `./scripts/check.sh` from the repo root before pushing changes.

Note: Home Manager seeds `~/.codex/config.toml` as a writable file for Codex
runtime preferences and owns shared global skills under `~/.agents/skills/`.
Codex discovers that standard location natively; Pi includes it through its
settings. Windows copies the same reviewed, vendored skill set through
`dotfile.ps1 ai`; no remote skill installer runs during setup. Agent-specific
plugins, packages, hooks, and generated runtime state
such as `skills-lock.json`, caches, and sessions stay native and out of the repo.

Note: Home Manager owns the `lazy.nvim` bootstrap package, and tracked
`lazy-lock.json` pins raw Neovim plugin state. Neovim uses Snacks pickers on all
platforms; `dotfile packages` and `dotfile update` restore the locked plugin set.
Failures are reported after the package operation.

Note: Home Manager profile ownership is explicit. Physical NixOS enables Linux
desktop, personal apps, Obsidian Sync, and Google Drive. NixOS-WSL uses the
separate `${hostName}-wsl` system target with no bootloader, hardware, desktop,
or personal-app configuration; `dotfile packages` selects it automatically.
Arch server enables Obsidian Sync, Google Drive, and storage backup, but no
desktop or personal apps. Generic Linux and macOS profiles keep optional groups
disabled. Linux desktop configuration is profile-gated, not merely OS-gated.

Arch server setup and full updates install the tracked service-state backup from
`config/arch-server/service-state-backup/` into `/usr/local/sbin` and
`/etc/systemd/system`, validate its live preflight, and enable its daily timer.
Generic Linux, NixOS, macOS, and AI-only updates do not install these root-owned
units.

`obsidian-headless` and `obsidian-sync` run on NixOS and Arch server. Obsidian GUI
and tracked GUI settings are personal-only. `dotfile obsidian` bootstraps
login/vault setup and restarts managed service; it reuses an existing configured
vault under `~/Documents` unless `-f` is passed.

Home Manager owns tracked Obsidian settings from `config/shared/obsidian` under
`~/Documents/Sync/.obsidian` on personal NixOS. Plugin bundles, themes,
workspace state, bookmarks, starred files, recent files, and Electron app state
stay out of the repo.

## Provisioning a fresh NixOS machine

On a freshly-installed NixOS box:

```bash
nix-shell -p git --run 'git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles && cd ~/dotfiles && bash ./dotfile packages'
```

Per-machine values live in tracked `config/host.nix`; hardware settings live in
tracked `config/hardware-configuration.nix`. Edit those files before the first
rebuild if the username, hostname, timezone, NixOS stateVersion, disks, or CPU
settings differ. Shared NixOS/WSL core settings live in `config/nixos/common.nix`;
hardware, desktop, and WSL-specific settings remain in their platform modules.
The package command performs initial NixOS activation and Home Manager setup.
The NixOS flake target is `#${hostName}` from `config/host.nix`; the current
tracked host uses `#nixos`.

On a brand-new machine, run this once before the first `switch` to confirm the
config evaluates:

```bash
sudo nixos-rebuild build --flake ~/dotfiles#${hostName}
```

After provisioning, use `dotfile update` to update managed dependencies. On Unix,
it refreshes every repository-managed pin, runs full checks, shows the resulting
uncommitted diff, then automatically approves and activates validated changes.
After successful activation, it commits the validated changes, fetches and rebases
if the upstream advanced, reruns checks on the rebased tree, and pushes the current
branch only if those checks pass. Existing unpublished
commits stop publication. Windows pulls and activates those published validated
pins instead of installing an unvalidated latest release; it reports when npm has
a newer Pi release awaiting publication.
Full updates install missing native prerequisites for the detected platform
before activating its configured profile; installed-state detection does not
select dependencies.
Use `dotfile update ai` to update only AI tools and configs. On Unix this
refreshes Codex and Pi release pins, managed AI packages, and Pi extensions with
the same isolated validation, diff display, and automatic approval. On Windows it
activates their published validated pins. On NixOS the full update ends with:

```bash
nix flake update --flake ~/dotfiles
sudo nixos-rebuild switch --flake ~/dotfiles#${hostName}
```

On macOS it uses existing `darwin-rebuild` when available:

```bash
sudo HOME=/var/root darwin-rebuild switch --flake ~/dotfiles#mac
```

If `darwin-rebuild` is not installed yet, it bootstraps through the pinned
`~/dotfiles#darwin-rebuild` app.

The `dotfile` command itself is installed by Home Manager on NixOS/macOS; use
`./dotfile` from the repo until the first rebuild has switched successfully.

## Testing

Bash tests run in the pinned Nix development shell. Requires Nix.

```bash
nix develop path:. -c bash tests/bash/runner.sh
nix develop path:. -c bash tests/bash/runner.sh test_utils.sh
```

PowerShell tests and Windows integrations require PowerShell, Node.js, and Neovim:

```powershell
./tests/powershell/runner.ps1
./tests/powershell/integration_pi_extensions.ps1
./tests/powershell/integration_neovim.ps1
```
