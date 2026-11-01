# Rex on macOS and Linux

macOS uses Rex. Linux retains tmux auto-attach/create of `main` and the bare
`tmux` convenience wrapper until a Linux Rex client is available. Shells already
inside Rex skip both; existing nested/embedded-shell guards and `NO_TMUX=1`
opt-out remain. Running processes are never transferred or terminated.

**Accepted Linux limitation:** only the server/automation CLI is released. There
is no interactive `rex attach` or public Linux GUI client yet. Linux/SSH starts
tmux on eligible interactive logins. Use the Mac app for interactive Rex sessions; Arch remote access is described below.

`debt:` a native Linux interactive cutover is limited by the released server-only
package. Revisit terminal launch/session entry when upstream releases its Linux
client; do not invent a capture/send terminal emulator or enable anonymous HTTP.

## Mac → Arch remote access

The Arch-server Home Manager profile in `flake.nix` enables
`services.rex.tailscale` with hostname `rex-quanarch`. Rex joins the tailnet as
its own device; it does not need the host's Tailscale daemon. Other Linux profiles
remain Unix-socket-only. Access is restricted to the enrolling Tailscale account:
neither anonymous access nor `allowTailnetMembers` is enabled. No Serve proxy,
Funnel, public firewall opening, or login server is used. MagicDNS and HTTPS
certificates must be enabled for the tailnet.

On the Mac, `config/darwin.nix` enables `services.tailscale.enable`. The pinned
nix-darwin module owns the CLI-only package and the boot-started launchd service
`com.tailscale.tailscaled`. We disable its static `/etc/resolver/ts.net` link:
Tailscale's confined resolver writes reject a symlink outside `/etc/resolver`
with `openat ts.net: path escapes from parent`. Tailscale owns and updates its
resolver files instead. It does not force all DNS through Tailscale
(`overrideLocalDns` stays false), configure an exit node, or advertise routes.
Login credentials, device identity, resolver files, and runtime preferences
remain native writable state outside Git and the Nix store.

Rex's embedded Tailscale exposes its server; it is not a documented outgoing
transport for the Mac client. The Mac's system Tailscale connection is still
needed to reach Arch, even if the Mac Rex server itself is enrolled.

### First Mac activation / migration from the GUI app

1. Disconnect the existing Tailscale GUI app, quit it, and disable its launch at
   login. Leave its app and identity intact for rollback. Do not run both clients
   connected at once; their identities are separate and are not migrated here.
2. Run `dotfile packages` from the updated checkout (set `DOTFILES_DIR` explicitly
   if using a task checkout). This uses the normal nix-darwin activation route
   and requires local sudo authentication. It starts the new daemon; Tailscale
   writes its own resolver files after enrollment. It does not restart Rex.
3. Enroll the Nix-managed client using the same Tailscale account that enrolled
   `rex-quanarch`:

   ```sh
   sudo /run/current-system/sw/bin/tailscale up --accept-dns=true --accept-routes=false
   ```

   Follow the login URL yourself. Never put an auth key or copied daemon state
   in the Nix source/store. The old `/usr/local/bin/tailscale` wrapper may still
   address the GUI app, so use the explicit managed path during migration.
4. Verify the real client and DNS/connection boundaries:

   ```sh
   command -v tailscale
   sudo launchctl print system/com.tailscale.tailscaled
   /run/current-system/sw/bin/tailscale status
   /run/current-system/sw/bin/tailscale ping --timeout=5s rex-quanarch.tail28b036.ts.net
   dscacheutil -q host -a name rex-quanarch.tail28b036.ts.net
   rex --server https://rex-quanarch.tail28b036.ts.net --autostart=false --timeout 5s whoami --json
   ```

If upgrading from the earlier static-resolver configuration, activation removes
only the stale Nix symlink. Restart the daemon once so it recreates its resolver
files (this briefly interrupts tailnet connections, but does not restart Rex):

```sh
sudo launchctl kickstart -k system/com.tailscale.tailscaled
/run/current-system/sw/bin/tailscale status
```

The DNS health warning should clear and `/etc/resolver/ts.net` should be a regular
file, not a Nix symlink. Tailnet policy must separately allow TCP 443 from your
Mac to the Rex device; a successful `tailscale ping` alone does not verify that.

Then open the managed Rex app and choose **Add Remote Host…**:

```text
https://rex-quanarch.tail28b036.ts.net
```

A successful connection permits programs to run as the Arch account, so never
replace this with anonymous HTTP or grant all tailnet users for convenience.
The saved host is application-owned state; adding a CLI host does not establish
that the GUI has added it. From Arch, `rex --autostart=false client ls` can confirm
a newly connected client and its identity. If the Mac cannot connect, check
online/account state, MagicDNS, HTTPS readiness, and ACLs before changing policy.

Before an Arch listener change, inspect sessions and coordinate the required Rex
restart; it ends sessions. Existing linger must be enabled for login-independent
use (`loginctl show-user "$(id -u)" -p Linger`). This setup does not silently enable
lingering or alter tailnet ACLs.

Mac rollback: run `sudo /run/current-system/sw/bin/tailscale down`, revert the
Mac `services.tailscale.enable` setting, and reactivate through `dotfile packages`
before reconnecting the preserved GUI app. Confirm the Nix daemon is stopped;
do not run both clients connected. Preserve both clients' identities.

Arch rollback: revert only its `services.rex.tailscale` stanza, build and activate
through `dotfile symlinks` after preserving/closing Rex sessions. Verify the Unix
socket still works. Do not reset Tailscale Serve, change SSH, or remove either
the host's or Rex's saved Tailscale identity.

## Command status in Rex shells

Zsh does not synthesize command-status reports for `dotfile`, `iib`, or
`cn2epub`. Programs such as Pi retain their native Rex status reporting.

## Shared configuration

`config/rex/init.lua` and `Catppuccin Macchiato.conf` deploy as the same two
Home Manager links on macOS and every Linux profile. Theme selection is still a
macOS client action; sharing the theme file does not theme Ghostty or a headless
Linux server. Linux package/service ownership remains in `config/rex-linux.nix`.

After activation, open a fresh shell; existing shells keep already-defined
functions until exited. Validate with `rex config check`, then explicitly run
`rex config reload` to apply the shared bindings without restarting sessions.
On macOS this requires running the managed app/version; Nix activation here is
not remote Mac deployment.

## macOS installation

## Ownership and activation

- `packages/rex-release.json` pins the official preview DMG by version, build, URL, and SHA-256. `dotfile update` refreshes it through the shared pin updater, requiring matching repeated downloads. The package build verifies the app's Apple signature and Superlogical team ID, and validates `init.lua` with the bundled CLI.
- Home Manager installs the app in `~/Applications/Home Manager Apps/` and exposes `rex` in PATH. Inside Rex, `REX_BIN_DIR` takes precedence so the CLI matches that server.
- `config/darwin.nix` owns native font preferences and disables Sparkle's automatic checks/installs. Upgrades and rollback use Nix generations, not the in-app updater. A pin change does not upgrade a running process.
- Only `~/.config/rex/init.lua` and `Catppuccin Macchiato.conf` are linked. Other Rex state, sessions, permissions, and settings remain native. Existing config conflicts are not forcibly overwritten; save and reconcile your file before activating.

### Which settings are tracked?

Git owns the keybindings and Catppuccin theme source (`config/rex/`), native preferences (`config/darwin.nix`), and release pin (`packages/rex-release.json`). The native theme import is a one-time seed, not continuous enforcement. Later GUI changes, imported theme storage, window layouts, sessions, and permissions are not exported back into Git or overwritten by the seed. Native preference defaults are reapplied by nix-darwin activation; edit their tracked source to change the managed baseline.

The saved baseline includes FiraCode Nerd Font at 14 pt and its fallbacks, Merino Light for light mode, focus-follows-mouse, compact panes, active-pane borders, fading both inactive-pane aspects, standard inactive-window pane styling, a left sidebar with vertical tabs and no icon tint, and copy-on-select. Agent session naming and developer mode are enabled; the server uses bundled mode with automatic restart enabled and plugin reload unblocked. The dark Catppuccin theme remains a portable one-time import, not a machine-specific theme UUID.

Remote-control permission, tailnet exposure, web-client origin permissions, sync hosts, cached server routes, onboarding/update history, window geometry, and session/activity state remain machine-local. These are not exported into Git. Sparkle automatic checks and installs remain disabled even if the live app changed them: Nix owns updates.

Run `dotfile packages`, then open `~/Applications/Home Manager Apps/Rex Beta.app`. Do not run it beside the older `/Applications` copy expecting a separate server: both use Rex's native account state. Save work and close the old sessions/app yourself before switching; provisioning does not terminate them.

For an already running app, `rex config check` validates the linked file and `rex config reload` applies its shortcuts without restarting terminals. Reload is explicit, not an activation side effect.

## macOS appearance

The native font preferences retain **FiraCode Nerd Font** and the existing Noto/symbol/emoji fallback list. macOS uses installed fallback faces; unavailable families fall back to the system. Nix already supplies the primary FiraCode Nerd Font.

Activation automatically imports **and selects Catppuccin Macchiato** through Rex's native `client.theme.import` action when exactly one local macOS app is connected. If Rex is closed, setup defers until a new interactive Rex shell starts; that attempt runs in the background without delaying the prompt. No app or server is started or restarted.

Successful setup writes `${XDG_STATE_HOME:-~/.local/state}/dotfiles/rex-theme-initialized`. Later activations and shells skip the import, preserving subsequent GUI theme choices. A missing/ambiguous client or permission refusal defers without a marker and does not block package activation; other import failures report an error and leave setup retryable. Concurrent attempts are serialized with a nonblocking OS lock. Remote server/home selections are ignored: only the current user's app on the standard local macOS socket is eligible.

The import preserves the ANSI palette, background, foreground, cursor, selection, and split-divider colors. **Ctrl+B, Shift+T** remains an explicit reimport-and-select shortcut. To reset the one-time seed deliberately, remove only the completion marker above, then open a new Rex shell or reactivate. Rex must allow client actions: enable **Settings → Rex Server → Remote Control** yourself before retrying if the app refuses. Setup never changes or bypasses that permission.

## tmux-style shortcuts

Keep Rex's native Cmd shortcuts, plus these sequences (press Ctrl+B, release, then the next key):

| Following key | Action |
| --- | --- |
| `c` | New tab |
| `p` / `n`, Ctrl+P / Ctrl+N | Previous / next tab |
| `1`–`9` | Go to tab (Rex numbers from 1) |
| `h` / `j` / `k` / `l` (also with Ctrl) | Focus left / down / up / right pane |
| `H` / `J` / `K` / `L` | Resize in that direction by 5% |
| `\|` or `%` | Split right |
| `-` or `"` | Split down |
| `<` / `>` | Move tab backward / forward |
| `z` | Zoom pane |
| `s` | Session picker |
| `R` | Reload Rex config |
| Ctrl+B | Send literal Ctrl+B to the terminal |
| `T` | Import the managed Catppuccin theme |

Splits and tabs use Rex's native current-directory behavior. Copy/paste use native **Cmd+C / Cmd+V**; Ctrl+C still interrupts the foreground program.

`debt:` Rex's exposed actions do not cover Ghostty's conditional Ctrl+C copy, tmux's vi copy mode, last-used tab, full-width splits, repeat-key resizing, or the custom user/host/date status line. Resize units are percentages rather than cells, and Rex manages scrollback itself. The migration ceiling is the documented Lua API plus actions exposed by the pinned client; add parity only when upstream exposes those capabilities. Ghostty's scroll multiplier and delayed quit have no managed Rex equivalent.

`debt:` Lua config does not expose persistent font/theme defaults. Fonts use the pinned app's native preference keys; theme setup uses the native client action and standard macOS local socket. The automation ceiling is one connected local app and an activation or new Rex shell; custom sockets or reopening only restored shells defer setup. Extend discovery/launch integration when those workflows are requested, or replace the seed with a declarative appearance API when Rex publishes one. Config validation alone does not establish font/rendering parity.

## Agents and status tracking

On macOS and Linux, activation runs the platform's pinned CLI's **`rex skill setup --agent pi`**, without `--force`. Rex owns the dynamic guide in `~/.agents/skills/rex`; a foreign skill is preserved. It calls the installed `rex skill show`, so instructions follow the installed version. Pi and other harnesses reading this shared directory can discover it. This is not a copied/vendored custom skill, and no Codex/Claude hook files are edited.

The pinned Pi already implements Rex's **Program Status Protocol (OSC 7501)** natively: working, blocked (dialogs/login), done, error, and idle. Detection is automatic inside Rex. No extension, title scraping, polling daemon, or extra `PI_PROGRAM_STATUS` override is needed. Reports contain status/session labels, not prompts or model output. Start a fresh Pi session inside Rex to discover the skill.

Check locally:

```sh
rex version
rex config check
rex skill status --json
rex skill show
```

To inspect a specifically identified agent pane without reading its screen/history:

```sh
rex --autostart=false --timeout 5s do -b "$REX_BLOCK" \
  com.superlogical.terminal.program_status --json
```

Use full session/pane IDs from the intended Rex context; do not inspect unrelated panes or restart a server to make status checks pass.
