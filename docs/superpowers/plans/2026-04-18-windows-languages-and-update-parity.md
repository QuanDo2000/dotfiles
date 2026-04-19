# Windows `languages` and `update` subcommand parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dotfile.ps1` accept all four language names under `languages` (with informative skip messages for the three not implemented on Windows) and add the missing `update` subcommand, matching bash `dotfile` parity.

**Architecture:** Pure additive changes to `dotfile.ps1`. Two new tiny wrapper functions (`Update-Packages`, `Update-Languages`), one rewritten dispatch (`Install-Languages`), one new switch case, two help-text edits. Tests extend the existing `test_gleam.ps1`, `test_usage.ps1`, and `test_args.ps1` files.

**Tech Stack:** PowerShell (`pwsh`). Test runner: `tests/powershell/runner.ps1` (framework-free, dot-sources `dotfile.ps1 -NoMain`).

**Related design spec:** `docs/superpowers/specs/2026-04-18-windows-languages-and-update-parity-design.md`

---

## File map

- **Modify** `dotfile.ps1`
  - Replace `Install-Languages` (currently `dotfile.ps1:511-517`)
  - Add `Update-Packages` and `Update-Languages` (insert after `Update-Gleam`, around `dotfile.ps1:509`)
  - Add `"update"` case to dispatch switch (`dotfile.ps1:742-749`)
  - Update `ShowUsage` (`dotfile.ps1:690-708`): rewrite `languages` line; add `update` line
- **Modify** `tests/powershell/test_gleam.ps1`
  - Extend the existing `Install-Languages` test block (after line 225) with cases for `zig`, `odin`, `jank`, `all`, `''`
  - Add `Update-Packages` dry-run test
  - Add `Update-Languages` no-op-when-gleam-missing test
- **Modify** `tests/powershell/test_usage.ps1`
  - Add `update` to the list of commands the help text must mention
- **Modify** `tests/powershell/test_args.ps1`
  - Add `update` to the positional-command recognition test

No new files are needed.

---

## Task 1: Add `Update-Packages` (TDD)

**Files:**
- Modify: `dotfile.ps1` (insert new function after `Update-Gleam` ~ line 509)
- Test: `tests/powershell/test_gleam.ps1` (append new test functions)

- [ ] **Step 1: Write the failing test**

Append to `tests/powershell/test_gleam.ps1`:

```powershell
# ---------------------------------------------------------------------------
# Update-Packages
# ---------------------------------------------------------------------------

function test_update_packages_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    try {
        $output = Update-Packages 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'Would run: scoop update *'
    Assert-False $called 'scoop should not be invoked in dry run'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: `FAIL  test_update_packages_dry_run_does_not_call_scoop` with an error mentioning that `Update-Packages` is not a recognized command.

- [ ] **Step 3: Implement `Update-Packages`**

In `dotfile.ps1`, immediately after the `Update-Gleam` function (which ends around line 509), insert:

```powershell
function Update-Packages {
    Info "Updating packages..."
    if ($script:Dry) { Success "Would run: scoop update *"; return }
    scoop update *
    Success "Finished updating packages"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: `PASS  test_update_packages_dry_run_does_not_call_scoop`. All other tests in the file still pass.

- [ ] **Step 5: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Add Update-Packages wrapper to dotfile.ps1"
```

---

## Task 2: Add `Update-Languages` (TDD)

**Files:**
- Modify: `dotfile.ps1` (insert after `Update-Packages`)
- Test: `tests/powershell/test_gleam.ps1` (append new test)

- [ ] **Step 1: Write the failing test**

Append to `tests/powershell/test_gleam.ps1`:

```powershell
# ---------------------------------------------------------------------------
# Update-Languages
# ---------------------------------------------------------------------------

function test_update_languages_calls_update_gleam_only {
    # Stub Update-Gleam to record invocation and produce a known marker.
    $sbUpdateGleam = (Get-Command Update-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Update-Gleam' -Value { Info 'STUB Update-Gleam called' }

    try {
        $output = Update-Languages 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Update-Gleam' -Value $sbUpdateGleam
    }

    Assert-Contains $output 'STUB Update-Gleam called'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: `FAIL  test_update_languages_calls_update_gleam_only` (Update-Languages not defined).

- [ ] **Step 3: Implement `Update-Languages`**

In `dotfile.ps1`, immediately after the new `Update-Packages` function, insert:

```powershell
function Update-Languages {
    Update-Gleam
    # zig is kept current via 'scoop update *' in Update-Packages.
    # odin/jank aren't installed by this script on Windows -- nothing to update.
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: `PASS  test_update_languages_calls_update_gleam_only`.

- [ ] **Step 5: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Add Update-Languages wrapper to dotfile.ps1"
```

---

## Task 3: Wire `update` into dispatch switch and `ShowUsage`

**Files:**
- Modify: `dotfile.ps1` (switch around line 742-749, ShowUsage around line 690-708)
- Test: `tests/powershell/test_args.ps1`, `tests/powershell/test_usage.ps1`

- [ ] **Step 1: Write the failing tests**

In `tests/powershell/test_usage.ps1`, modify `test_showusage_mentions_all_commands` to include `update`:

```powershell
function test_showusage_mentions_all_commands {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    foreach ($cmd in 'all', 'packages', 'extras', 'symlinks', 'languages', 'verify', 'update') {
        Assert-Contains $output $cmd
    }
}
```

In `tests/powershell/test_args.ps1`, modify `test_parseargs_positional_command_recognised` to include `update`:

```powershell
function test_parseargs_positional_command_recognised {
    foreach ($c in 'packages', 'extras', 'symlinks', 'verify', 'update') {
        $script:Dry = $false
        $result = ParseArgs @($c)
        Assert-Equals $c $result
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh tests/powershell/runner.ps1 test_usage.ps1` and `pwsh tests/powershell/runner.ps1 test_args.ps1`
Expected for `test_usage.ps1`: `FAIL  test_showusage_mentions_all_commands` — output does not contain `update`.
Expected for `test_args.ps1`: PASS (ParseArgs is permissive — any positional becomes the command). Document this; the assertion still locks the contract for future regressions.

- [ ] **Step 3: Implement the dispatch and usage changes**

In `dotfile.ps1`, edit `ShowUsage` (around line 690-708). Replace the existing `Commands:` block so it reads:

```
Commands:
  all         Run full setup (default)
  update      Update system packages and language toolchains
  packages    Install system packages only
  extras      Install fonts
  symlinks    Create symlinks only
  languages [LANG]  Install language toolchains. LANG selects one (only gleam is installed on Windows; zig comes from 'packages').
  verify      Verify installation
```

In `dotfile.ps1`, edit the dispatch switch (around line 742-749). Add the `update` case so the switch becomes:

```powershell
    switch ($command) {
        "all"       { SetupDotfiles }
        "update"    { Update-Packages; Update-Languages }
        "packages"  { InstallPackages }
        "extras"    { InstallExtras }
        "symlinks"  { SetupSymlinks }
        "languages" { Install-Languages -Target $script:CommandArg }
        "verify"    { Verify }
        default     { Fail "Unknown command: $command"; ShowUsage }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh tests/powershell/runner.ps1`
Expected: All tests PASS, including the two updated ones.

- [ ] **Step 5: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_usage.ps1 tests/powershell/test_args.ps1
git commit -m "Wire 'update' subcommand into dotfile.ps1 dispatch and help"
```

---

## Task 4: Expand `Install-Languages` (TDD)

**Files:**
- Modify: `dotfile.ps1` (replace `Install-Languages` around line 511-517)
- Test: `tests/powershell/test_gleam.ps1` (extend the `Install-Languages` test block)

- [ ] **Step 1: Write the failing tests**

Append to `tests/powershell/test_gleam.ps1` (after the existing `test_install_languages_*` tests):

```powershell
function test_install_languages_zig_emits_scoop_message {
    $output = Install-Languages -Target 'zig' 6>&1 | Out-String
    Assert-Contains $output 'scoop'
}

function test_install_languages_odin_emits_unsupported_message {
    $output = Install-Languages -Target 'odin' 6>&1 | Out-String
    Assert-Contains $output 'odin'
    Assert-Contains $output 'not wired up'
}

function test_install_languages_jank_emits_unsupported_message {
    $output = Install-Languages -Target 'jank' 6>&1 | Out-String
    Assert-Contains $output 'jank'
    Assert-Contains $output 'Linux/macOS only'
}

function test_install_languages_all_runs_gleam_and_skips_others {
    $sbInstallGleam = (Get-Command Install-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    try {
        $output = Install-Languages -Target 'all' 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Gleam' -Value $sbInstallGleam
    }

    Assert-Contains $output 'STUB Install-Gleam called'
    Assert-Contains $output 'Skipping zig'
    Assert-Contains $output 'Skipping odin'
    Assert-Contains $output 'Skipping jank'
}

function test_install_languages_empty_target_behaves_like_all {
    $sbInstallGleam = (Get-Command Install-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    try {
        $output = Install-Languages -Target '' 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Gleam' -Value $sbInstallGleam
    }

    Assert-Contains $output 'STUB Install-Gleam called'
    Assert-Contains $output 'Skipping zig'
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: All five new tests FAIL — the current `Install-Languages` calls `Fail "Unknown language: zig"` etc., which throws via the existing test stub setup OR returns no message matching the new assertions. The `all` test will pass but won't see the `Skipping zig` text.

- [ ] **Step 3: Replace `Install-Languages`**

In `dotfile.ps1`, replace the existing function (lines 511-517):

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

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh tests/powershell/runner.ps1 test_gleam.ps1`
Expected: All `Install-Languages` tests PASS, including the existing `test_install_languages_dispatches_gleam_only` and `test_install_languages_unknown_fails`.

- [ ] **Step 5: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Expand Install-Languages to recognize zig/odin/jank with skip messages"
```

---

## Task 5: Full-suite regression check

**Files:** none (verification only)

- [ ] **Step 1: Run the entire PowerShell suite**

Run: `pwsh tests/powershell/runner.ps1`
Expected: `=== Results: N passed, 0 failed, N total ===` with exit code 0.

- [ ] **Step 2: Smoke-check the live commands**

Run each of the following and confirm exit code 0 and reasonable output:

```bash
pwsh dotfile.ps1 -h | grep -E '(update|languages)'
pwsh dotfile.ps1 -d languages zig
pwsh dotfile.ps1 -d languages odin
pwsh dotfile.ps1 -d languages jank
pwsh dotfile.ps1 -d languages gleam
pwsh dotfile.ps1 -d languages
pwsh dotfile.ps1 -d update
```

Expected:
- `-h` output contains both `update` and the new `languages [LANG]` line.
- `languages zig` prints the scoop message.
- `languages odin` and `languages jank` each print their respective skip messages.
- `languages gleam` and `languages` (default `all`) run `Install-Gleam` (in dry mode).
- `update` runs `Update-Packages` then `Update-Languages` (both dry-mode safe).

- [ ] **Step 3: No commit**

This task is verification only. If anything fails, return to the appropriate earlier task.

---

## Self-Review Notes

- **Spec coverage:**
  - `Install-Languages` rewrite → Task 4
  - `Update-Packages` → Task 1
  - `Update-Languages` → Task 2
  - `update` switch case → Task 3
  - `ShowUsage` updates → Task 3
  - `tests/powershell/test_languages.ps1` (extend or create) → covered by extending `test_gleam.ps1` (which already owns the `Install-Languages` tests; no need to fragment)
  - `tests/powershell/test_cli.ps1` (extend) → covered by Task 3 changes to `test_args.ps1` + `test_usage.ps1` (PowerShell tests don't subprocess the dispatch — they assert via `ParseArgs` and `ShowUsage`)
  - Acceptance criterion "all four language names exit 0" → Task 4 step 1 tests + Task 5 step 2 smoke check
  - Acceptance criterion "`-d update` works" → Task 5 step 2
- **Placeholders:** none.
- **Type consistency:** `Install-Gleam`, `Update-Gleam`, `Info`, `Fail`, `Success`, `Set-Item function:script:*`, `Set-CommandMock`, `Clear-CommandMock`, `Assert-Contains`, `Assert-False` are all existing names verified against `dotfile.ps1` and `tests/powershell/helpers.ps1`. `$script:Dry`, `$script:CommandArg` match the existing globals in `Reset-DotfileState`.
- **Note on test placement:** the spec mentioned `tests/powershell/test_languages.ps1` and `test_cli.ps1` as candidate file names. Neither exists today — `test_gleam.ps1` already owns the `Install-Languages` tests, and `test_args.ps1`/`test_usage.ps1` cover the CLI surface. Following the existing structure rather than creating new files keeps the diff smaller and matches the established pattern.
