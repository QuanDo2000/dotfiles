# Windows/Linux Installation Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make Windows setup, update, configuration ownership, and health checks match the Unix lifecycle without copying Linux-only features.

**Architecture:** Keep dotfile.ps1 as the Windows entry point. Reuse shared package lists and existing Python seed scripts so install and doctor cannot drift.

**Tech Stack:** PowerShell 7, Winget, Scoop, fnm, npm, Python 3.14, existing framework-free PowerShell tests.

## Global Constraints

- Do not enable FFF, global AGENTS links, Linux desktop packages, zsh/tmux, or Obsidian Headless on Windows.
- Use exact package IDs and post-install command checks.
- Preserve verify as a compatibility alias for doctor.
- Write tests before each production change.

---

### Task 1: Shared manifests and trustworthy doctor

**Files:** dotfile.ps1, tests/powershell/test_package_checks.ps1, tests/powershell/test_verify.ps1, tests/powershell/test_usage.ps1

- [ ] Add failing tests for shared manifests, exact package checks, complete command checks, and doctor.
- [ ] Run focused tests and confirm failures identify missing behavior.
- [ ] Add manifest functions and manifest-driven doctor checks; retain verify.
- [ ] Run focused tests and confirm they pass.

### Task 2: AI tools and Pi

**Files:** dotfile.ps1, tests/powershell/test_ai_install.ps1

- [ ] Add failing tests for AI postconditions, Pi installation/update, and Pi writable seeds.
- [ ] Run AI tests and confirm expected failures.
- [ ] Install Pi, validate all AI commands, and seed Pi settings and MCP files.
- [ ] Run AI tests and confirm they pass.

### Task 3: Complete updates

**Files:** dotfile.ps1, tests/powershell/test_extras.ps1, tests/powershell/test_update_packages.ps1

- [ ] Add failing tests that update only managed Scoop packages and refresh Node LTS.
- [ ] Run focused tests and confirm failures.
- [ ] Make InstallExtras update Scoop packages and Node, and call it from Update-Packages.
- [ ] Run focused tests and confirm they pass.

### Task 4: Writable LazyVim configuration

**Files:** dotfile.ps1, tests/powershell/test_symlinks.ps1, tests/powershell/test_lazyvim.ps1

- [ ] Add failing tests for migrating the legacy directory link, linking stable files, and seeding writable lazyvim.json.
- [ ] Run focused tests and confirm failures.
- [ ] Implement migration and invoke existing lazyvim.py through Python 3.14.
- [ ] Run focused tests and confirm they pass.

### Task 5: Least-privilege links and workflow postchecks

**Files:** dotfile.ps1 and existing Windows orchestration tests.

- [ ] Add failing tests proving ordinary commands do not self-elevate, failed link privilege elevates one encoded operation, and setup/update invoke doctor.
- [ ] Run focused tests and confirm failures.
- [ ] Remove blanket elevation, add one-operation link fallback, and add post-workflow doctor calls.
- [ ] Run focused tests, then the complete PowerShell suite.
- [ ] Run git diff --check and read-only doctor.
