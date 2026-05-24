# AI tools install (Claude Code, OpenCode) — design spec

**Date:** 2026-05-23
**Status:** Approved (pending user spec review)
**Scope:** Add `claude` and `opencode` to the default `dotfile packages` install flow on Debian/Ubuntu, Arch, and macOS. Wire both into `dotfile update` so they refresh on each update run. The repo already tracks their configs under `config/shared/ai/{claude,opencode}/` and symlinks them; this spec covers the binaries themselves.

## Goal

After `dotfile packages` completes, `claude` and `opencode` are on PATH on all three Unix-family platforms. After `dotfile update`, both binaries are at their latest released version via each tool's built-in self-updater.

Both tools install via their vendor-recommended one-line scripts:

- **Claude Code:** `curl -fsSL https://claude.ai/install.sh | bash`
- **OpenCode:** `curl -fsSL https://opencode.ai/install | bash`

Both install scripts work on Linux and macOS, so a single platform-agnostic `setup_*` function per tool covers all three platforms (no Debian/Arch/Mac branching inside the function).

## Non-goals

- npm-based install paths (`npm install -g @anthropic-ai/claude-code` / `opencode-ai`). Vendors' native scripts are simpler and don't drag Node into the package list.
- Homebrew on macOS for either tool. The official scripts are the chosen install path on all platforms for consistency.
- Pinning to specific versions — always latest.
- Installing plugins, marketplaces, or model credentials. Plugin enablement is already tracked in `config/shared/ai/claude/settings.json` and `config/shared/ai/opencode/opencode.json`; this spec is binaries only.
- Adding `claude` / `opencode` to `verify.sh`'s `REQUIRED_TOOLS`. The install-side `command -v` short-circuit is the only check; verify stays AI-tool-agnostic.
- Adding a `dotfile ai` subcommand — AI tools are part of the baseline package install, not opt-in.
- Windows-side changes (`dotfile.ps1`). Out of scope for this round.

## CLI surface

No new subcommands. Both tools install as part of the existing flow:

```
dotfile packages          # installs claude + opencode alongside existing tooling
dotfile update            # runs `claude update` and `opencode upgrade`
dotfile verify            # unchanged
```

## Files added / changed

| File | Action | Responsibility |
|---|---|---|
| `scripts/packages.sh` | Modify | Add `setup_claude_code` and `setup_opencode`. Wire into `install_debian`, `install_arch`, `install_mac`, `update_debian`, `update_arch`, `update_mac`. |
| `tests/bash/test_packages.sh` | Modify | Add tests for both functions (dry-run, already-installed, update-does-not-skip). |

No changes to `verify.sh`, `symlinks.sh`, `dotfile.ps1`, or any Windows test.

## Implementation

### `setup_claude_code [--update]`

```bash
function setup_claude_code {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} Claude Code..."
  if [[ "$DRY" == "false" ]]; then
    if command -v claude >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        claude update || fail "Failed to update Claude Code"
      else
        info "Already installed Claude Code"
      fi
    else
      curl -fsSL https://claude.ai/install.sh | bash \
        || fail "Failed to install Claude Code"
    fi
  fi
  success "Finished Claude Code"
}
```

- Install: `curl … | bash` only when the binary is absent.
- Update: when the binary is present and `--update` is passed, delegate to `claude update` (the CLI's built-in self-updater).
- Already-installed fast-path (no `--update`): log and return.

### `setup_opencode [--update]`

Same shape as `setup_claude_code`, with these substitutions:

- Binary name: `opencode`
- Install URL: `https://opencode.ai/install`
- Update command: `opencode upgrade`
- Log labels: "OpenCode"

### Integration points in `packages.sh`

```
install_debian:
  ...existing setup_* calls...
  setup_claude_code
  setup_opencode

install_arch:
  ...existing setup_* calls...
  setup_claude_code
  setup_opencode

install_mac:
  ...existing brew calls...
  setup_claude_code
  setup_opencode

update_debian:
  ...existing --update calls...
  setup_claude_code --update
  setup_opencode --update

update_arch:
  ...existing --update calls...
  setup_claude_code --update
  setup_opencode --update

update_mac:
  ...existing brew upgrade...
  setup_claude_code --update
  setup_opencode --update
```

Both new functions go at the end of the existing `setup_*` block in `packages.sh` (after `setup_brew_linux`), keeping AI tooling visually grouped at the bottom of the file.

## Tests

All in `tests/bash/test_packages.sh`, following the existing `setup_*` test conventions (source helpers, `init_test_env`/`cleanup_test_env`, no real network).

### `setup_claude_code`

- `test_setup_claude_code_dry_run` — `DRY=true`; assert output contains "Claude Code" and "Finished".
- `test_setup_claude_code_already_installed` — stub `claude` on PATH via `$HOME/.local/bin/claude`; `DRY=false`; assert "Already installed Claude Code".
- `test_setup_claude_code_update_dry_run` — `--update` with `DRY=true`; assert "Updating Claude Code" and "Finished".
- `test_setup_claude_code_update_does_not_skip` — `--update` with stub `claude` on PATH; assert output does NOT contain "Already installed".

### `setup_opencode`

Same four tests, swapping the binary name and log strings.

### CLI dispatch

No new subcommand, so no new test in `test_cli.sh`.

### Helper notes

The "already installed" tests need a fake binary on PATH. Pattern used elsewhere in the suite:

```bash
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$HOME/.local/bin/claude"
PATH="$HOME/.local/bin:$PATH"
```

`init_test_env` already sets `$HOME` to a throwaway temp dir, so PATH mutation is contained to the test.

## Risk & rollback

- **`curl | bash` pattern:** consistent with `setup_brew_linux:199` which already bootstraps Homebrew the same way. Both vendors publish these scripts as the recommended install path. Not a new risk surface for this repo.
- **Install URL for Claude Code:** `https://claude.ai/install.sh` is the publicly documented installer. If Anthropic moves it, `fail` triggers and the rest of `install_*` continues; user resolves manually. Worth re-checking at implementation time.
- **Self-updater drift:** if `claude update` or `opencode upgrade` ever change their flag surface or exit codes, `update_*` runs fail loudly via `fail`. Easy to swap to re-running the install script.
- **Mac without Homebrew preinstalled:** `install_mac` already bootstraps brew first, then the AI tool install runs. The install scripts themselves don't require brew, so this only matters for ordering — placing the AI calls after the existing brew block is sufficient.

Rollback is per-tool:
- Claude Code: `claude uninstall` (built-in), or remove its install dir under `~/.local/share/`.
- OpenCode: `opencode uninstall` (built-in), or remove its install dir.

Removing the wiring from `packages.sh` and the tests is a single revert.
