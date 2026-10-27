# Rex on macOS and Linux

Rex is the default managed session system on both Unix platforms. Shell startup
does not start/attach tmux, and no `tmux` shell function is installed. Linux keeps
the package and legacy config for explicit fallback; running processes are never
transferred or terminated by this configuration migration.

**Accepted Linux limitation:** only the server/automation CLI is released. There
is no interactive `rex attach` or public Linux GUI client yet. Linux/SSH starts
a normal shell. Use the Mac app for interactive Rex sessions; this cutover does
not configure remote network access.

`debt:` a native Linux interactive cutover is limited by the released server-only
package. Revisit terminal launch/session entry when upstream releases its Linux
client; do not invent a capture/send terminal emulator or enable anonymous HTTP.

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
