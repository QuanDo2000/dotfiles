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

All Linux profiles declare Unix-socket-only Rex servers. Mac → Arch uses native
OpenSSH over the machine's existing Tailscale network:

```text
ssh://quando@100.98.211.17
```

The Mac GUI connection and a fresh app quit/reopen were verified against the
Arch client list: a new Mac app connection used the Unix socket through
`sshd-session: quando` and reattached to the same session. System Tailscale on
both machines remains necessary; only Rex's separate embedded Tailscale/HTTPS
listener is being retired. Do not remove system Tailscale, SSH keys, ACLs, or
saved Rex Tailscale identity. No anonymous HTTP or public port is introduced.

### Configure the Mac client

Use **Add Remote Host…** with the explicit SSH address above. CLI `rex.host`
declarations do not currently synchronize into the Mac GUI. Home Manager supplies
`rex-quanarch-ssh` for CLI use only; activating or reloading it is not GUI setup.
The shared `quanarchRemote` alias resolved on Arch but failed on the actual Mac;
the explicit account/address avoids relying on unverified client alias setup.

During migration, editing the existing HTTPS entry reverted, while removing and
re-adding the GUI entry as SSH succeeded. The cause of the reverted edit is
unknown. Before deliberately removing a saved GUI host, record its URL/name/icon
for rollback. Removing a GUI host is not a server-session deletion. Read back the
saved URL, then check the actual transport; seeing the same host or sessions is
not transport evidence.

```sh
# On the Mac: discovery/CLI check, not GUI acceptance.
ssh -o BatchMode=yes quando@100.98.211.17 'command -v rex; rex version'
rex -S ssh://quando@100.98.211.17 --autostart=false --timeout 10s server status
# On Arch: match the connected macos app, excluding lost entries and CLI probes.
rex --autostart=false client ls --json
```

Linux Home Manager links `~/.local/bin/rex` to the pinned binary for discovery
from noninteractive SSH shells. The upstream Home Manager service uses
`X-SwitchMethod = "keep-old"`; activation does not replace the running server.

### Session-safe listener retirement

The source removes `services.rex.tailscale` and the obsolete HTTPS CLI host.
**The live listener remains until a coordinated, session-safe restart.** Build
and dry-run the Arch profile before activation. Use the normal role-aware route
`DOTFILES_DIR=/path/to/reviewed/checkout /path/to/reviewed/checkout/dotfile symlinks`;
inspect other pending changes before applying a broader profile update.

Before restarting, inspect `rex --autostart=false ls --json` and connected clients.
A restart terminates all programs in Rex: defer while user sessions are in use.
After saving work and intentionally closing sessions, activate and deliberately
run `systemctl --user restart rex`. Verify the unit has no `--tailscale`, system
Tailscale remains running, and Mac SSH reconnect still reaches Rex. Linger must
remain enabled (`loginctl show-user "$(id -u)" -p Linger`).

Rollback: restore the prior reviewed `services.rex.tailscale` stanza with hostname
`rex-quanarch`, build/dry-run/activate through the same route, then coordinate
another session-safe restart. Retain the embedded identity so re-enrollment is
not required. The former GUI URL was
`https://rex-quanarch.tail28b036.ts.net`; it is usable only while that listener
is running. Do not reset Tailscale Serve or the system daemon.

For native activity, **Ctrl+B, a** opens View Activity. On the Mac, use
**Show Activity by Priority**, and under **Settings → Notifications → Program
Activity** enable per-pane rows and blocked/error notifications, leaving working
notifications quiet. These are application-owned choices, not inferred preference
keys written by Nix. Pi already reports its status natively; no polling dashboard
or synthetic shell-status hooks are needed.

## Command status in Rex shells

Zsh does not synthesize command-status reports for `dotfile`, `iib`, or
`cn2epub`. Programs such as Pi retain their native Rex status reporting.

## Shared configuration

`config/rex/init.lua` supplies the shared keybindings on every Unix profile.
Home Manager appends the CLI-only Arch SSH host declaration on macOS; Linux links the
shared Lua file unchanged. `Catppuccin Macchiato.conf` remains a shared link. Theme selection is still a
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

Remote-control permission, tailnet exposure, web-client origin permissions, other saved hosts and host overrides, cached server routes, onboarding/update history, window geometry, and session/activity state remain machine-local. These are not exported into Git. Sparkle automatic checks and installs remain disabled even if the live app changed them: Nix owns updates.

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
| `a` | Native program activity picker |
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
