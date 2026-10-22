# Cross-client replication and pilots

Paths below are relative to this reference directory.

When extending a completed tool benchmark to another supported agent client (for example Pi → Codex):

1. Inventory live integrations first. Separate an installed, executable client with an active tool registration from stale configuration, hooks, or skill files. Benchmark only runnable clients; do not turn a missing client into a durable negative claim.
2. Reuse the frozen repository revision, workloads, mutations, rubrics, tests, and ground truth. Add only the smallest client adapter; do not redesign the benchmark per client or compare results collected under different task suites as if they were paired.
3. Prove the client's fresh-session command, machine-readable event/usage schema, isolated config-home override, and one-feature A/B structural diff with a quarantined smoke run before canonical collection.
4. Preserve the target client's real production setup in A. In B, remove only the candidate server/tool exposure; retain instructions, skills, model, reasoning, sandbox, approvals, and every unrelated integration.
5. Keep client suites serial when they share host load, provider quota, repository fixtures, or candidate daemons. Record the client/version and loaded-host provenance in every result.
6. For a cheaper pilot, keep all substantive workload classes but use one paired trial per workload and set a predeclared cost ceiling. Validate the exact reduced matrix and label the verdict exploratory. Never change production configuration from a one-trial pilot; require the normal seven-trial matrix for confirmation.
7. If a client does not emit cost or a token category, report that metric as unavailable rather than deriving it from another client's accounting.
8. If the candidate is selected in zero eligible runs, interpret the suite as an **exposure-overhead/natural-nonuse pilot**, not a test of candidate utility. Keep the production matrix unforced; diagnose discoverability or run an explicitly labeled forced-use supplement separately.
9. Keep correctness levels explicit. When one workload is blind-scored and others use hidden mechanical tests, report workload-level passes separately from hidden-test pass counts so a valid aggregate cannot be mistaken for a contradictory one.

See `cross-client-pilots.md` for the reduced-matrix evidence and interpretation checklist. See `codex-cross-client-benchmarks.md` for the validated Codex adapter, accounting, live-state audit, and support-policy pitfalls.
