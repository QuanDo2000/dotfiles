# Default AI policy across agent runtimes

Use this when dotfiles must make behavioral guidance active at every agent startup, not merely installed or discoverable.

## Choose the ownership model first

### Fixed always-on policy

Use this when the user does not need runtime level changes or stop commands:

- Embed a concise, behavior-complete policy in the startup file.
- Codex and Pi share global `AGENTS.md`; Hermes needs the equivalent policy in `$HERMES_HOME/SOUL.md`.
- Remove startup hooks/extensions that only inject that policy.
- Remove base mode and mode-help skills that only select or explain levels.
- Keep skills with distinct workflows, such as audits, reviews, compression, commit generation, or debt analysis.

This is the smaller design: one startup policy per runtime family, no duplicate injection path, and no required skill load before the first response.

### Switchable mode

Keep hooks/base skills when users still require any of these:

- per-session enable/disable;
- intensity changes;
- stop commands;
- dynamic injection into child agents that do not inherit startup files.

Those mechanisms are behavior, not redundant scaffolding. Test every supported transition.

## Migration workflow

1. Inventory each hook and base skill. Separate fixed policy text from commands, state, status UI, and child-injection behavior.
2. Confirm startup-file loading for main and child agents. Do not assume Hermes consumes global `AGENTS.md`; use `SOUL.md`.
3. Write the smallest startup policy that preserves the intended implementation and communication constraints.
4. Delete only level-changing hooks/base/help skills. Preserve task-oriented skills.
5. Update source manifests, Home Manager links, platform installers, generated-copy lists, and parallel Bash/PowerShell/macOS expectations.
6. Add explicit cleanup for copy-based installers. Removing a filename from a Windows copy list does not delete a previously installed hook or skill.
7. Delete obsolete hook-specific tests, then search the complete repository for fixtures that named those tests or files indirectly.
8. Run the focused policy/installer tests, full Bash and PowerShell suites, ShellCheck, all-system flake evaluation, and remote CI for the exact commit SHA.

## Verification matrix

For each runtime, distinguish:

1. **Startup policy present**: deployed `AGENTS.md` or `SOUL.md` contains the fixed rules.
2. **Duplicate injector absent**: retired hook files are neither configured nor deployed.
3. **Redundant mode skill absent**: base and help skills are no longer installed.
4. **Functional skills retained**: workflow skills still resolve.
5. **Child behavior covered**: child agents inherit the startup policy or have an intentional equivalent path.
6. **Fresh-session semantics checked**: existing sessions can retain old prompts; verify in a new session.

## Platform ownership

- Home Manager removes retired managed links on activation.
- Copy-based Windows installers need explicit stale-file deletion for both hooks and skills.
- Git-backed flakes omit untracked inputs; track every referenced startup or skill source before treating evaluation as clean-checkout proof.
- Do not activate a generic Home Manager target merely to test this migration. Use the repository's host-role router and preserve unrelated service/session state.

## Post-migration consolidation audit

- Compare complete trigger, scope, workflow, and output contracts before calling two skills duplicates. Shared vocabulary is not duplication when one skill reviews a diff and another audits a whole tree, or when one applies judgment and another mechanically inventories exact markers.
- Keep conditional operational detail out of always-loaded policy. A one-line global root-cause or regression-check rule does not replace a debugging hypothesis workflow, TDD RED proof, or review evidence contract.
- Treat explicit installer removal and negative tests for retired hooks/skills as migration compatibility, not dead code. Users can skip releases, so copy-based stale cleanup should remain unless a versioned migration boundary proves it obsolete.
- Separate tracked declarative configuration from ignored runtime state such as a native skill lockfile. Do not turn local catalog cleanup into a dotfiles change unless tracked code owns that file.
- End the audit when remaining candidates have distinct behavior. Cosmetic stale test names or messages alone do not justify a standalone refactor commit.

## Common pitfalls

- Copying the entire old skill text into every startup file preserves unnecessary prompt bulk. Condense it while retaining trust-boundary, data-loss, accessibility, root-cause, and verification rules.
- Deleting hooks before proving child inheritance can silently change subagent behavior.
- Updating Linux assertions alone leaves Windows or macOS CI enforcing the retired inventory.
- Confusing a loaded startup hook with deployed state: activation or skill reload removes files/catalog entries, but the current process can keep the old injector in memory. Verify absence on disk and in a genuinely fresh session.
- A green local suite is not remote proof; query and monitor the workflow run for the pushed full SHA.
