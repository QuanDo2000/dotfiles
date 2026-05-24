# `caf` — Mac caffeinate toggle script

## Goal

Add a small `caf` command, Mac-only, that toggles `caffeinate` on and off. Running `caf` once starts `caffeinate -d -i` in the background (preventing display sleep and idle sleep). Running `caf` again kills that background process. No arguments, no flags — just a toggle.

## Location and wiring

- New file: `config/mac/bin/caf` (executable, `chmod +x`).
- No changes to `scripts/symlinks.sh` are needed. `setup_symlinks_folder` already symlinks any `<layer>/bin/*` into `~/.local/bin/`, and `setup_symlinks` only applies the `config/mac/` layer when `is_mac` returns true. So on macOS, `~/.local/bin/caf` → `dotfiles/config/mac/bin/caf` automatically on next `dotfile symlinks` run.

## Behavior

```
$ caf
caf: ON (pid 12345)

$ caf
caf: OFF
```

### State

A single PID file at `/tmp/caf.pid` tracks the running `caffeinate` process. `/tmp` is wiped by macOS at boot, so no stale state survives reboots.

### Toggle logic

1. If `/tmp/caf.pid` exists and the PID it names is alive (checked with `kill -0 $pid 2>/dev/null`):
   - `kill $pid`
   - `rm /tmp/caf.pid`
   - Print `caf: OFF` and exit 0.
2. Otherwise (file missing, or file present but PID is dead — stale):
   - If the file is stale, remove it.
   - Launch `nohup caffeinate -d -i >/dev/null 2>&1 &`.
   - Write `$!` to `/tmp/caf.pid`.
   - Print `caf: ON (pid <N>)` and exit 0.

### Why a PID file (not `pkill caffeinate`)

`caffeinate` is invoked by many other tools (some app installers, `asar`, certain background helpers). Killing every `caffeinate` in sight would interfere with them. The PID file tracks only the instance `caf` started.

### Why `caffeinate -d -i`

- `-i` prevents idle sleep (CPU-side).
- `-d` keeps the display on.
- No `-u` — we don't want to simulate user activity (which would unlock screensaver locks, etc.).
- No `-s` — that only works on AC power and is more aggressive than needed.

## Script shape

```bash
#!/bin/bash
set -eu

PID_FILE=/tmp/caf.pid

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    rm -f "$PID_FILE"
    echo "caf: OFF"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

nohup caffeinate -d -i >/dev/null 2>&1 &
echo "$!" > "$PID_FILE"
echo "caf: ON (pid $!)"
```

~20 lines. No external deps beyond `caffeinate` itself.

## Tests

Add to `tests/bash/test_symlinks.sh` a case verifying that under `mock_uname Darwin`, running `setup_symlinks` produces `~/.local/bin/caf` as a symlink pointing at `config/mac/bin/caf`. Mirror the existing `test_setup_symlinks_folder_bin` pattern but exercise the Mac-branch end-to-end.

Behavioral tests for the toggle itself are out of scope — they would require either a real `caffeinate` binary (Mac-only, not available in the Linux CI/Docker test env) or mocking the binary, which adds more machinery than the script warrants. Consistent with this repo's existing test philosophy ("dry-run smoke + branch coverage", per `CLAUDE.md`).

No CLI dispatch test is needed because `caf` is a standalone script, not a `dotfile` subcommand.

## Out of scope

- Duration arguments (`caf 30m`) — explicitly rejected; toggle-only.
- Wrapping a command (`caf npm run build`) — same.
- Other platforms — Linux equivalents (`systemd-inhibit`, `xset`) are intentionally not handled.
- Status query (e.g. `caf status`) — toggle-only keeps it simple; check `[ -f /tmp/caf.pid ]` directly if needed.
