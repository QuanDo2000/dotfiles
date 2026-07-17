# Remaining Windows Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows package lifecycle and writable Codex configuration match the Unix-managed behavior.

**Architecture:** Reuse the existing package functions through one shared flow, and make update call the existing repository/package installers instead of duplicating Winget upgrade logic. Add a Windows-only Codex seed and reuse the existing Python seed comparator.

**Tech Stack:** PowerShell 7, Winget, Scoop, Python 3.14, existing PowerShell test runner

## Global Constraints

- Install Gpg4win with exact Winget ID `GnuPG.Gpg4win`.
- Keep FFF, global AGENTS links, Unix shared skills, zsh/tmux, Obsidian Headless, and Linux desktop services excluded.
- Codex runtime config must remain a regular writable file.
- Do not add a pre-update doctor on Windows.

---

### Task 1: Complete package lifecycle

**Files:**
- Modify: `dotfile.ps1:176-290,451-464,726-734,788-792`
- Test: `tests/powershell/test_package_checks.ps1`
- Test: `tests/powershell/test_setupdotfiles.ps1`
- Test: `tests/powershell/test_update_packages.ps1`

**Interfaces:**
- Consumes: `InstallPackages`, `InstallExtras`, `InstallAi`, `UpdateRepo`
- Produces: `InstallManagedPackages`, complete `packages`, repository-aware `update`

- [ ] **Step 1: Add failing lifecycle tests**

Require `GnuPG.Gpg4win`, verify `InstallManagedPackages` calls all three existing installers, and verify `Update-Packages` calls `UpdateRepo` then `InstallPackages` before update-only installers.

```powershell
Assert-True ($winget -contains 'GnuPG.Gpg4win') 'Winget should manage Gpg4win'

$script:Calls = @()
Set-FunctionMock 'InstallPackages' { $script:Calls += 'winget' }
Set-FunctionMock 'InstallExtras' { $script:Calls += 'extras' }
Set-FunctionMock 'InstallAi' { $script:Calls += 'ai' }
InstallManagedPackages
Assert-Equals 'winget extras ai' ($script:Calls -join ' ')
```

- [ ] **Step 2: Verify RED**

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_package_checks.ps1 test_setupdotfiles.ps1 test_update_packages.ps1
```

Expected: failures for missing Gpg4win, missing `InstallManagedPackages`, and missing update calls.

- [ ] **Step 3: Implement the shared lifecycle**

Add `GnuPG.Gpg4win` to `Get-WingetPackages`, add this shared function, use it from `SetupDotfiles` and `packages`, and replace the direct Winget block in `Update-Packages` with `UpdateRepo` and `InstallPackages`:

```powershell
function InstallManagedPackages {
    InstallPackages
    InstallExtras
    InstallAi
}
```

- [ ] **Step 4: Verify GREEN**

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_package_checks.ps1 test_setupdotfiles.ps1 test_update_packages.ps1
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit lifecycle changes**

```powershell
git add dotfile.ps1 tests/powershell/test_package_checks.ps1 tests/powershell/test_setupdotfiles.ps1 tests/powershell/test_update_packages.ps1
git commit -m "feat(windows): complete managed package lifecycle"
```

### Task 2: Seed writable Codex configuration

**Files:**
- Create: `config/windows/ai/codex/config.toml`
- Modify: `dotfile.ps1:293-402,624-714`
- Test: `tests/powershell/test_ai_install.ps1`
- Test: `tests/powershell/test_verify.ps1`

**Interfaces:**
- Consumes: `scripts/seed_merge/codex.py`, `Invoke-NativeChecked`
- Produces: `SyncCodexConfig`, `%USERPROFILE%\.codex\config.toml`

- [ ] **Step 1: Add failing Codex seed tests**

Create a temporary Windows seed, run `SyncCodexConfig`, and require a regular writable target. Add a doctor assertion for a missing target.

```powershell
SyncCodexConfig
$target = Join-Path $env:USERPROFILE '.codex\config.toml'
Assert-FileExists $target
Assert-False ([bool](Get-Item $target).LinkType) 'Codex config should stay writable'
```

- [ ] **Step 2: Verify RED**

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_ai_install.ps1 test_verify.ps1
```

Expected: failure because `SyncCodexConfig` and the Windows seed do not exist.

- [ ] **Step 3: Create the Windows-safe seed**

Create `config/windows/ai/codex/config.toml` with the shared model, notice, TUI, marketplace, plugin, codebase-memory approval, and feature settings. Use this Windows MCP command and omit FFF and Unix project paths:

```toml
[mcp_servers.codebase-memory-mcp]
command = "codebase-memory-mcp"
```

- [ ] **Step 4: Implement and call `SyncCodexConfig`**

Use the same copy-or-compare pattern as the Unix activation:

```powershell
function SyncCodexConfig {
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $source -Destination $target
        return
    }
    $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { '' } else { $source }
    Invoke-NativeChecked 'Codex config seed comparison failed' {
        py -3.14 (Join-Path $script:DotfilesDir 'scripts\seed_merge\codex.py') $target $source $applySeed
    }
}
```

Call it from `InstallAi`, and make `Verify` fail when the target is missing or is a symlink.

- [ ] **Step 5: Verify GREEN**

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_ai_install.ps1 test_verify.ps1
```

Expected: all focused tests pass.

- [ ] **Step 6: Commit Codex seed changes**

```powershell
git add config/windows/ai/codex/config.toml dotfile.ps1 tests/powershell/test_ai_install.ps1 tests/powershell/test_verify.ps1
git commit -m "feat(windows): seed writable Codex config"
```

### Task 3: Documentation and end-to-end verification

**Files:**
- Modify: `README.md:94-108`

**Interfaces:**
- Consumes: completed package and Codex flows
- Produces: accurate Windows command documentation

- [ ] **Step 1: Update README**

Add `doctor` to the Windows command list and change the packages description to `Install all managed packages only`.

- [ ] **Step 2: Run complete verification**

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1
pwsh -NoProfile -File .\dotfile.ps1 -d all
pwsh -NoProfile -File .\dotfile.ps1 all
pwsh -NoProfile -File .\dotfile.ps1 doctor
git diff --check
```

Expected: tests report zero failures, dry run exits zero, setup installs or verifies Gpg4win and all managed packages, doctor reports all checks passed, and diff check exits zero.

- [ ] **Step 3: Commit documentation**

```powershell
git add README.md docs/superpowers/plans/2026-07-16-windows-remaining-parity.md
git commit -m "docs: update Windows package commands"
```
