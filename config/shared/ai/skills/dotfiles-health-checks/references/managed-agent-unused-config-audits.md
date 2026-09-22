# Managed-agent unused-configuration audits

Use this checklist to distinguish dead configuration from defaults, caches, and intentionally dormant capability.

## Evidence layers

For every configured feature, inspect independently:

1. **Declarative ownership** — tracked Unix/macOS/Windows seeds, activation hooks, tests, and package declarations.
2. **Live state** — effective config, installed package identity, extension registry, active process/listener, and service or scheduler state.
3. **Runtime surface** — toolsets actually exposed to each platform, prerequisite/provider availability, and background polling or startup cost.
4. **Usage** — structured tool calls, task/run database rows, scheduler run history, and feature-specific state events. Use text search only as supporting evidence because source reads and prompts create false positives.
5. **Intent** — explicit on-demand retention, rollback value, paused/resumable workflow, or superseding implementation.

Record each source's coverage. CLI, gateway, subagent, scheduler, desktop, and external-app logs often have different retention and blind spots.

## Classification

- **active:** recent structured use or required by a verified live workflow.
- **deliberately dormant:** disabled/on-demand by design; retain unless the capability itself is abandoned.
- **stale metadata:** discovery/cache/catalog entry with no package or runtime route; remove only if it will not simply regenerate.
- **unavailable:** enabled declaration but missing required provider, executable, or credential. Disable unless near-term setup is intentional.
- **unused:** available and exposed, with representative retained history showing zero use and no explicit retention intent.
- **superseded:** old pipeline replaced by a verified active path; remove the old job plus uniquely-owned scripts/config.

## Scheduler rules

- Completed bounded retry represented as an infinite paused schedule: delete job and unique script.
- Never-run or paused pipeline with a verified successor: delete after checking no active job depends on its output/context.
- Paused recurring monitor with no successor: keep paused unless the user abandons the monitored workflow.
- Empty task database plus enabled dispatcher: report actual idle cost; disable only when the feature is unwanted, not to chase negligible resource savings.

## Reporting

Rank findings:

1. Safe removal: stale metadata, completed one-shots, superseded jobs.
2. Strong disable: unavailable or exposed-but-unused capabilities.
3. Review: intentionally paused monitors and weak/incomplete usage evidence.
4. Keep: verified use, deliberate on-demand capability, or cleanup whose installer/test diff exceeds its runtime benefit.

For each finding include the exact owned objects, structured evidence, behavioral consequence, and smallest reversible change. Correct overbroad prior claims explicitly—for example, “no active integration remains; discovery metadata still mentions it.” Do not mutate anything during an audit-only request.

## Applying an approved cleanup

1. Snapshot the live config and concurrent worktree state before mutation.
2. Prefer the application's native config/tool commands, then inspect both the raw persisted file and resolved values. An `unset` can correctly remove an override while `get` still displays the built-in default.
3. Re-run discovery only when needed. Discovery and tool-management commands may repopulate `known_*` catalog metadata; if an inactive entry returns without an enabled runtime route, classify it as generated availability metadata and stop trying to delete it.
4. Treat multi-item mutation output as potentially partial. Read back each platform toolset and each scalar flag rather than trusting a zero exit status or aggregate success line.
5. Remove scheduler records first, verify retained jobs and dependency links, then delete only scripts uniquely owned by the removed jobs.
6. Separate persisted-state verification from activation verification. Config syntax, raw values, and scheduler readback do not prove a long-running gateway adopted startup-only settings; require a fresh process identity or fresh-session surface before claiming activation.
7. After restart, verify the new gateway process/start time, config check, retained scheduler jobs, and retired listeners. If status still calls the service definition outdated, diff the installed unit against a freshly generated expected unit before restarting again. A PATH-only difference can come from the caller shell (for example NVM versus Nix) and is not evidence that cleanup failed; repeat restart only when the difference changes runtime behavior.

## Model-route review

Use structured `session_model_usage` records, grouped by billing provider, model, and task, rather than transcript mentions. Keep a configured fallback when it has handled real calls, even if it is quiet in recent gateway logs. Review main, delegation, auxiliary, and scheduled-job routes separately because each serves a different workload.

Treat resolved/default configuration carefully: migration or restart can regenerate an inactive MoA preset or other built-in defaults after an explicit unset. Verify activation fields and exposed toolsets before calling that regeneration a cleanup regression. Dormant provider credentials have no model-call cost by themselves; remove them only for credential hygiene or when the user abandons the provider, not to simplify active routing.