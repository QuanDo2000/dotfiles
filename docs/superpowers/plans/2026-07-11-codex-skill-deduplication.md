# Codex Skill Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the complete Superpowers plugin with three pinned skills and remove duplicate local skill/cache state.

**Architecture:** Home Manager pins `obra/superpowers` at tag `v6.1.1` and owns three complete skill directories. The tracked and live Codex configs stop enabling the plugin; local duplicate skills and caches are deleted only after activation proves the replacements exist.

**Tech Stack:** Nix, Home Manager, TOML, Bash tests

## Global Constraints

- Retain only `systematic-debugging`, `test-driven-development`, and `verification-before-completion` from Superpowers.
- Preserve complete upstream skill directories and their companion files.
- Keep specialized Caveman skills and the OpenAI templates cache.
- Verify declarative activation before deleting runtime caches.

---

### Task 1: Declare the retained skills

**Files:**
- Modify: `tests/bash/test_nixos_config.sh`
- Modify: `config/home.nix`

**Interfaces:**
- Produces: Home Manager paths `.codex/skills/{systematic-debugging,test-driven-development,verification-before-completion}`.

- [ ] Add a failing test asserting the pinned `obra/superpowers` source, the three managed directories, and absence of other Superpowers directory entries.
- [ ] Run `bash tests/bash/runner.sh --no-docker test_nixos_config.sh`; expect the new assertions to fail.
- [ ] Add `superpowersSrc = pkgs.fetchFromGitHub` with revision `c984ea2e7aeffdcc865784fd6c5e3ab75da0209a` and hash `sha256-kHdQ9e44doBk2yYW88tMSCqVG8ycYcvJSZlrIziXhpA=`.
- [ ] Add the three directory sources to `home.file` using the existing `forceSource` helper.
- [ ] Re-run the focused test; expect all tests to pass.

### Task 2: Disable the full plugin

**Files:**
- Modify: `config/shared/ai/codex/config.toml`
- Modify: `$HOME/.codex/config.toml`

**Interfaces:**
- Removes: `[plugins."superpowers@openai-curated"]` from tracked and live configuration.

- [ ] Remove the two-line plugin table from both TOML files.
- [ ] Parse both files with Python `tomllib`; expect exit code 0.

### Task 3: Activate and verify

**Files:**
- Runtime: `$HOME/.codex/skills/`

- [ ] Run the current Home Manager switch for this host.
- [ ] Verify each retained skill directory and its `SKILL.md` resolve to a Nix store source.
- [ ] Verify no Home Manager entry manages any other Superpowers skill.

### Task 4: Remove duplicate runtime state

**Files:**
- Delete: `.agents/skills/caveman/`
- Delete: `.agents/skills/cavecrew/`
- Delete: `$HOME/.codex/plugins/cache/openai-curated/superpowers/`
- Delete: `$HOME/.codex/plugins/cache/openai-curated-remote/superpowers/`
- Delete: `$HOME/.codex/plugins/.marketplace-plugin-source-staging/`

- [ ] Confirm global Caveman matches the local duplicate, then remove only the local duplicate and Cavecrew.
- [ ] Remove only the two Superpowers cache trees and abandoned staging checkout.
- [ ] Confirm specialized Caveman skills and OpenAI templates remain.

### Task 5: Final verification

**Files:**
- Verify: `config/home.nix`
- Verify: `config/shared/ai/codex/config.toml`
- Verify: `tests/bash/test_nixos_config.sh`

- [ ] Run `./scripts/check.sh`; expect all Bash, PowerShell, Nix, build, and ShellCheck checks to pass.
- [ ] Run `git diff --check`; expect no output.
- [ ] Review `git status --short` and confirm only the plan and tracked configuration/test changes remain.
