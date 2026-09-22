# Subagent extension benchmark coverage

Use this reference when benchmarking removal or replacement of a configurable subagent/orchestration extension.

## Coverage model

Do not multiply every feature by every repeated workload. Use two layers:

1. **Surface coverage (once per frozen variant):** prove every enabled role, workflow mode, control path, and non-default setting is exercised or explicitly verified.
2. **Decision matrix (production A/B):** repeat representative quality, latency, token, and cost workloads for at least seven serial trials per variant.

Freeze the installed extension version, live/declarative configuration, model routing, prompts, repositories, checks, and trial order before provider calls. Record a machine-readable coverage manifest mapping each advertised/current capability and setting to a test cell or explicit exclusion reason. Disabled roles/features are still checked as unavailable; unsupported or inactive optional integrations are not silently counted as covered.

## Inventory before design

Read the installed-version README and reference docs, not only remembered feature names. Compare live settings with their managed source and inventory:

- enabled, disabled, and overridden agent roles;
- default and per-role model/thinking routes;
- strict model scope and tool restrictions;
- foreground/background defaults and observability/control paths;
- concurrency, per-run, per-session, timeout, tool, and usage budgets;
- artifact/output location and description/prompt mode;
- isolation, acceptance, structured output, supervisor, mission, and schedule behavior;
- any enabled nested delegation, external runner, watchdog, or UI observer integration.

## Representative use cases

At minimum cover each enabled role in its intended use: code reconnaissance, external research, implementation, review, and independent second opinion. Cover single delegation, sequential chaining, parallel and dynamic fanout, implement-review-fix, isolated writers/worktrees, acceptance gates, structured/file outputs, background status/wait/steer/resume/stop, supervisor decisions, missions, and schedules when enabled.

Use mutation-capable disposable worktrees for implementation tasks. Grade with hidden executable checks, blind adjudication, independent result reparse, canonical matrix validation, checksums, and cleanup proof. Natural-use A/B measures adoption and default-exposure overhead; a separate forced-use supplement is required before concluding that an explicitly invoked capability has no utility.

## Offline-first construction and gates

Build and exercise the harness before provider collection:

1. Pin the requested historical commit explicitly. If the live branch advances during setup, retain the declared immutable commit, record the observed live head as provenance, and clone/check out the pin for every disposable worktree.
2. Copy the declarative settings plus every immutable package closure those settings reference into a temporary agent home. Never retain `auth.json`, sessions, or runtime logs. Variant B removes exactly the candidate package and the minimum top-level role/settings references that would otherwise be invalid.
3. Compare the declared candidate version with the installed package manifest and record a version-drift notice rather than silently relabeling the benchmark.
4. Make provider execution opt-in (`--allow-provider`). Pilot mode is one interleaved A/B pair; full mode refuses to start without explicit cost and wall-time ceilings.
5. Prove hidden graders outside the mutable worktree against known ground-truth target trees. Run Python compilation, static coverage/preflight, matrix-plan generation, cleanup, and independent checksum reparse without provider calls.

For candidate edits, a trusted external grader should run after every cell, save only non-secret evidence (diff, status, metrics), remove the worktree/config in `finally`, and stop the serial matrix on the first **invalid execution**. A valid execution may legitimately fail its hidden correctness check; record that as score `0`, not as a harness abort.

### Harness traps found in practice

- Resolve the candidate package from the copied settings entry. Do not inspect a similarly named legacy install path; verify the resolved manifest version before pilot calls.
- Copy nested configuration to the runtime's canonical location (for Pi subagents: `extensions/subagent/config.json`). A convenient root-level copy proves inventory only and silently benchmarks defaults.
- Static documentation/source markers prove that a capability exists, not that it was exercised. The coverage manifest must point to an upstream executable test, a current-config runtime smoke, a natural matrix cell, or a justified exclusion.
- Immutable extension closures may contain read-only directories and symlinks into a package store. Cleanup must unlink symlinks without chmod-following them and make owned copied directories writable before recursive removal. Prove prepare→cleanup→prepare succeeds before spending on a pilot.
- Treat the first complete A/B pilot as a gate: both cells must retain raw events, parse inclusive parent/child usage, grade independently, remove credentials/worktrees, and leave no owned process. Freeze projection only from that successful pair; failed setup attempts are provenance, not canonical cells.

## Decision rule

Do not claim comprehensive coverage from representative workloads alone. The coverage manifest proves breadth; repeated production cells estimate effects. If one enabled capability lacks either a test or a justified exclusion, the benchmark is incomplete.
