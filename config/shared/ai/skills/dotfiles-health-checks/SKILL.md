---
name: dotfiles-health-checks
description: "Validate dotfiles and Home Manager changes against repository checks and affected deployed behavior."
version: 1.3.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [dotfiles, home-manager, nix, system-health, verification]
    related_skills: [systematic-debugging, test-driven-development]
---

# Dotfiles Health Checks

Use after an update/activation or for a requested health assessment. Governing authority and delivery policy applies throughout, including references: diagnosis is read-only; repairs, activation, publication, and cleanup require their applicable authorization. Do not activate or inspect unrelated services for source-only policy edits.

## Verification flow

1. **Scope and snapshot.** Record source revision, staged/unstaged/untracked state, affected surfaces, deployed role, and current generation. Preserve concurrent work. Serialize conflicting host-wide activations/service changes even when tasks use different repositories; rerun checks if their environment changes.
2. **Resolve ownership.** Inspect source, deployed links, runtime state, and actual command owner separately. Ordinary ad-hoc installs remain native unless reproducible provisioning is requested. Never edit store targets or application-owned state as though it were a declarative source.
3. **Choose native checks.** Read repository instructions and router flow. Run focused checks plus required full gates on the current revision. Build before authorized activation. Do not refresh pins or pull merely to activate a worktree. Use the deployed role router/helper, never an inferred generic target or a bypass of the role guard—even for dry runs.
4. **Check affected live behavior.** After deployment, verify resolved links/binaries and the real changed operation: shell login, editor startup, scratch tmux, service status/logs, MIME executable plus desktop entry, or application tool interface. Package presence and source tests do not establish runtime behavior. Use isolated HOME/XDG/data for trials.
5. **Interpret results.** Inspect exit status and decisive output: activation hooks and editors can print failures despite exit zero. A successful Home Manager stage followed by failed privileged setup is partial completion, not total failure; verify the generation and report the pending stage with the native rerun. Do not start a desktop or mask a backend merely to hide a headless/session mismatch.
6. **Repair only confirmed regressions.** Reproduce first, patch the owning source under approval, verify, and re-activate only if authorized. Git flakes omit untracked inputs: `path:` can diagnose this, but track required inputs for clean-checkout delivery. Never stage unrelated files.
7. **Read back.** Reinspect diffs after checks/activation: seed hooks and concurrent writers can change the same files. Verify the exact deployed artifact and affected behavior. Distinguish source changed, live deployed, and fresh-session behavior verified. Report passed/failed/skipped/unverified checks, final worktree state, and rollback handles.

## Load only the relevant procedure

References preserve specialized contracts; they are not a checklist to run against every host. Read `references/operational-boundaries.md` for CI, instruction/updater changes, package-removal audits, or signing changes.

| Surface | Procedure |
|---|---|
| Git-flake inputs, MIME, session targets | `references/home-manager-nix-pitfalls.md` |
| Authorized dirty-worktree pull | `references/autostash-pull-conflicts.md` |
| Service data-path migration | `references/stateful-service-path-migrations.md` |
| Host-role packages/files/units | `references/host-scoped-home-manager-features.md` |
| Standalone Linux root-owned files | `references/standalone-linux-root-system-files.md` |
| Missing role packages/timers, backup watchdog | `references/profile-drift-watchdog-alerts.md` |
| Headless GUI unit failure | `references/headless-gui-user-units.md` |
| Managed code-search/MCP stack | `references/ai-code-search-stack-audit.md` |
| Nix wrappers and cross-platform PowerShell | `references/nix-ownership-and-cross-platform-powershell.md` |
| Always-loaded policy versus runtime modes | `references/ai-agent-default-modes.md` |
| Mutable seeds versus authoritative policy | `references/managed-agent-config-authority.md` |
| Unused agent configuration | `references/managed-agent-unused-config-audits.md` |
| Signed publishing/concurrent staging | `references/headless-git-publishing.md` |
| Isolated editor trial | `references/isolated-editor-config-trials.md` |
| Dependency ownership replacement | `references/dependency-ownership-prototypes.md` and `references/operational-boundaries.md` |
| GUI package replacement | `references/gui-package-replacement-validation.md` |
| Stateful agent extension cutover | `references/managed-agent-extension-replacements.md` |
| Writable-memory trust boundary | `references/untrusted-memory-context-hardening.md` |
| Locked npm CLI companion | `references/locked-npm-cli-companions.md` |
| One SSH client's tmux opt-out | `references/client-specific-tmux-opt-out.md` |

Keep credentials opaque. Do not inspect raw session/history stores automatically; establish an agreed bounded source/time scope before attribution searches. A missing audit trail means caller unknown, not user blame.
