# GitHub CLI on Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install and verify GitHub CLI through the existing Windows package manifests.

**Architecture:** Add the official Winget ID and executable name to the two existing manifests. Existing install, update, and doctor code consumes those manifests, so no new installer path is needed.

**Tech Stack:** PowerShell, Winget, existing PowerShell test runner

## Global Constraints

- Use Winget package ID `GitHub.cli`.
- Verify executable name `gh`.
- Do not add special-case installation logic.

---

### Task 1: Manage GitHub CLI

**Files:**
- Modify: `dotfile.ps1:176-195`
- Test: `tests/powershell/test_package_checks.ps1`

**Interfaces:**
- Consumes: `Get-WingetPackages` and `Get-RequiredCommands`
- Produces: `GitHub.cli` package management and `gh` doctor verification

- [ ] **Step 1: Write the failing manifest test**

Add command collection and assertions to `test_windows_package_manifests_cover_parity_tools`:

```powershell
$commands = @(Get-RequiredCommands)
Assert-True ($winget -contains 'GitHub.cli') 'Winget should manage GitHub CLI'
Assert-True ($commands -contains 'gh') 'Doctor should verify GitHub CLI'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_package_checks.ps1
```

Expected: `test_windows_package_manifests_cover_parity_tools` fails because both entries are absent.

- [ ] **Step 3: Add the two manifest entries**

Add `GitHub.cli` to `Get-WingetPackages` and `gh` to `Get-RequiredCommands` in `dotfile.ps1`.

- [ ] **Step 4: Verify focused and full tests**

Run:

```powershell
pwsh -NoProfile -File tests/powershell/runner.ps1 test_package_checks.ps1
pwsh -NoProfile -File tests/powershell/runner.ps1
```

Expected: focused test passes and full suite reports zero failures.

- [ ] **Step 5: Apply and diagnose the real workflow**

Run:

```powershell
pwsh -NoProfile -File .\dotfile.ps1 all
pwsh -NoProfile -File .\dotfile.ps1 doctor
```

Expected: Winget installs `GitHub.cli` if missing, `gh` is found, and doctor reports all checks passed.

- [ ] **Step 6: Commit**

```powershell
git add dotfile.ps1 tests/powershell/test_package_checks.ps1
git commit -m "feat(windows): install GitHub CLI"
```
