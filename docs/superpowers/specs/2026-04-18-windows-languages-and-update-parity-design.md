# Windows `languages` and `update` subcommand parity

## Background

`dotfile.ps1` lags behind the bash `dotfile` script in two ways:

1. **`Install-Languages` only handles `gleam`.** Bash supports `zig`, `odin`, `gleam`, and `jank`. On Windows, asking for any of the other three fails with `Unknown language: <name>`. The PowerShell `ShowUsage` text also says only `gleam`.
2. **No `update` subcommand.** Bash exposes `dotfile update` → `update_packages` + `update_languages`. PowerShell's switch (`dotfile.ps1:742-749`) has no `update` case and `ShowUsage` doesn't mention it.

This is "option A" from the audit: close the gap by acknowledging the other languages without porting their installers. zig, odin, and jank stay unimplemented on Windows; users get a clear message instead of an error.

## Constraints / context

- **zig is already installed via scoop** on Windows (`dotfile.ps1:248`, `scoopPkgs` array). The `languages` subcommand should point users there rather than implying zig is missing.
- **odin** has Windows binaries but no installer is wired up in this repo.
- **jank** is Linux/macOS only by design (no upstream Windows support) — see `docs/superpowers/specs/2026-04-18-jank-language-install-design.md`.
- `Install-Gleam` and `Update-Gleam` already exist and stay unchanged.
- `InstallPackages` already runs `scoop update *` on every invocation (`dotfile.ps1:259-260`); `Update-Packages` will duplicate that one line rather than refactoring the install path.

## Design

### `Install-Languages` (replace existing function in `dotfile.ps1`)

```powershell
function Install-Languages {
    param([string]$Target = 'all')
    switch ($Target) {
        { $_ -in @('all', '') } {
            Install-Gleam
            Info "Skipping zig: installed via scoop on Windows (run 'dotfile.ps1 packages')"
            Info "Skipping odin: no Windows installer wired up"
            Info "Skipping jank: Linux/macOS only (no Windows support upstream)"
        }
        'gleam' { Install-Gleam }
        'zig'   { Info "zig is installed via scoop on Windows; run 'dotfile.ps1 packages'" }
        'odin'  { Info "odin install is not wired up for Windows" }
        'jank'  { Info "jank is Linux/macOS only (no Windows support upstream)" }
        default { Fail "Unknown language: $Target" }
    }
}
```

Behavior contract:

- `all` and `''` → install gleam, emit info for the other three, exit 0.
- `gleam` → install gleam, exit 0.
- `zig`, `odin`, `jank` → emit a single info message, exit 0 (no `Fail`).
- Any other value → `Fail` (preserves existing typo-protection).

### `update` subcommand

Add two new functions in `dotfile.ps1`:

```powershell
function Update-Packages {
    Info "Updating packages..."
    if ($script:Dry) { Success "Would run: scoop update *"; return }
    scoop update *
    Success "Finished updating packages"
}

function Update-Languages {
    Update-Gleam
    # zig is kept current via 'scoop update *' in Update-Packages.
    # odin/jank aren't installed by this script on Windows — nothing to update.
}
```

Wire into the dispatch switch (`dotfile.ps1:742-749`):

```powershell
"update"    { Update-Packages; Update-Languages }
```

### `ShowUsage` updates

- Replace the current `languages` line so it lists all four names and notes the gleam-only caveat:
  `languages [LANG]  Install language toolchains. LANG selects one (only gleam is installed on Windows; zig comes from 'packages').`
- Add a new line: `update      Update system packages and language toolchains`.

## Tests

### `tests/powershell/test_languages.ps1` (extend or create)

- `Install-Languages -Target gleam` calls `Install-Gleam` (mocked) once.
- `Install-Languages -Target zig` returns 0 and emits an info message containing "scoop".
- `Install-Languages -Target odin` returns 0, emits info, no `Fail`.
- `Install-Languages -Target jank` returns 0, emits info, no `Fail`.
- `Install-Languages -Target all` calls `Install-Gleam` once and emits the three skip messages.
- `Install-Languages -Target bogus` triggers `Fail` (i.e. throws / exits non-zero).

### `tests/powershell/test_cli.ps1` (extend)

- `dotfile.ps1 -d update` exits 0 (dry-run path).
- `dotfile.ps1 -h` output includes the literal token `update`.

Use the existing pattern: dot-source `dotfile.ps1 -NoMain`, override globals via `$script:Dry`, capture output with `*>&1 | Out-String`.

## Out of scope

- Porting zig/odin/jank installers to PowerShell.
- Refactoring `InstallPackages` to share the `scoop update *` call.
- Touching the bash side — both subcommands already work there.
- Adding bash test changes — bash `update`/`languages` are already covered.

## Acceptance criteria

- `dotfile.ps1 languages zig|odin|jank|gleam|all` all exit 0 with the documented behavior.
- `dotfile.ps1 -d update` and `dotfile.ps1 update` both run without erroring.
- `dotfile.ps1 -h` lists `update` and the corrected `languages` description.
- All PowerShell tests in `tests/powershell/` pass via `pwsh tests/powershell/runner.ps1`.
