# Pi subagent concurrency and model-scope audits

Use this when configuring or reviewing Pi Subagents. Values that sound global often govern different lifetimes.

## Concurrency keys

- `parallel.maxTasks`: maximum task entries accepted by one parallel invocation.
- `parallel.concurrency`: simultaneously active tasks inside that parallel invocation.
- `globalConcurrencyLimit`: simultaneously running child tasks within one run/chain/async run. It is not a session- or process-wide semaphore.
- `maxSubagentSpawnsPerSession`: cumulative spawn budget across a session. It is not a live-concurrency cap; setting it to seven prevents later delegation after seven total launches.

Do not assume those settings govern the currently advertised API. In `pi-subagents` 0.45.2, legacy `tasks` execution was removed in favor of `workflowScript`; review the shipped `runs.all()` implementation because an unbounded `Promise.all` can bypass legacy `parallel.*` controls, and per-run semaphores are not one shared workflow/session semaphore. Re-check this on every extension upgrade rather than preserving the version-specific claim forever.

With `asyncByDefault: true`, separate detached runs can overlap and each can reach its own run-local limit. Therefore declarations such as `globalConcurrencyLimit: 7` plus `parallel.concurrency: 7` express intended native limits but do **not** by themselves prove an absolute “one main plus seven children” ceiling.

Prefer the native limit plus an operational rule of one large swarm at a time. Add a session-wide scheduler/semaphore only when strict global enforcement is an observed requirement; do not substitute a cumulative spawn cap and call it equivalent.

## Model-scope semantics

In `pi-subagents`, `subagents.modelScope.enforce` hard-rejects explicit caller-supplied out-of-scope models. Out-of-scope models inherited from role frontmatter, defaults, parent sessions, or fallbacks can warn rather than fail for compatibility. Project-local settings can also change effective scope after trust approval.

Treat model scope as a routing guardrail, not a security sandbox. Audit:

1. effective role models after defaults/frontmatter/overrides;
2. fallback models;
3. project-local settings and trust state;
4. provider authentication and actual model catalog.

## Declarative deployment

Pi Subagents keeps runtime config at `~/.pi/agent/extensions/subagent/config.json`, separate from the main Pi settings file.

When managing it through dotfiles:

- deploy the nested path on every supported platform;
- track the seed before claiming clean-checkout reproducibility;
- decide whether the file is a mutable seed or authoritative policy;
- remember that a three-way writable seed merger can preserve live limit increases and write them back to the repository;
- if a concurrency ceiling is policy, deploy that file authoritatively and fail activation when synchronization fails;
- replace both the live target and its merge baseline through same-directory temporary files, set explicit owner-writable permissions (for example `0600`), then rename into place;
- on Windows, use the same temp-and-rename pattern rather than an interruptible direct overwrite;
- test stale live-value restoration, fresh creation, nested parent creation, and Windows/Linux paths;
- delete the baseline once in a fixture or controlled smoke test, activate twice, and verify exact contents, permissions, no leftover temporary files, and repeatability.

A direct copy from a read-only package/store source can create a read-only baseline on first activation; the second activation then fails when trying to overwrite it. Explicit permissions plus atomic replacement prevent this subtle non-idempotence.

## Verification wording

Report only the strongest claim exercised against the active API. If tests merely inspect JSON, say “configured native seven-child limits,” not “enforced seven-child cap.” Claim a per-run, workflow-wide, session-wide, or process-wide ceiling only after a runtime fan-out test proves that exact lifetime. When native enforcement is incomplete, pair the config with explicit parent instructions limiting children per workflow and forbidding overlapping workflows. Fresh Pi sessions may be required because already-running sessions can retain startup configuration.
