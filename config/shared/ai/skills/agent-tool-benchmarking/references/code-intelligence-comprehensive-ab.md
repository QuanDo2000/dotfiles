# Comprehensive code-intelligence removal benchmark

Use this after a read-only ablation suggests removing an eager repository index/graph tool. A read-only tie is evidence about eager loading, not universal removal.

## Freeze advertised scope first

Before trial 1, inventory capabilities from both:

1. the exact installed binary's version, help, and live MCP schemas;
2. authoritative documentation for that same release.

Write a requirement-to-workload-to-tool matrix. Every advertised capability must map to a scored cell or an explicit `unverified` reason. Do not silently substitute current upstream documentation for an older installed release.

Typical graph-tool surface includes repository indexing/status/deletion, project listing, graph/schema queries, architecture, code and structural search, snippets, path tracing, change detection, coverage inspection, ADRs, and trace ingestion. Treat these as examples; the live schema is authoritative.

## Three separately reported suites

### 1. Production-shaped agent A/B

- A: normal agent setup plus the eager candidate.
- B: identical normal setup without only the candidate and stale tool references.
- Prompts request outcomes naturally; never force A to use the tool.
- Track candidate selection. An installed-but-unused tool proves overhead only.
- Use seven paired trials for noisy provider-backed workloads, alternating launch order and rotating workload order.

Include at least six distinct normal warm workflows: architecture/package-boundary reconstruction with impact tracing; root-cause localization plus minimal fix; caller-preserving API refactor; bounded multi-package behavior change; test-gap discovery plus regression repair; and security/data-validation repair. Also cover symbol/code/semantic/structural search, dead/complex code audit, implementation planning, and cross-service/cross-package understanding within those cells. Two mutation prompts are not a representative normal-use suite.

Weight the decision explicitly: routine warm indexed work should contribute about 90% of the primary verdict. One-time lifecycle and specialized conformance contribute about 10%, reported separately, unless they expose a catastrophic safety, data-loss, or reliability failure.

### 2. Mutation and lifecycle A/B

Use fresh disposable clones/worktrees per cell. Allow edits and score executable artifacts:

- incremental change detection after edits;
- API rename/move with hidden caller and compatibility tests;
- stale index after rename/delete, followed by recovery;
- partial-index and excluded-file coverage behavior;
- cold index, warm reuse, and long-lived-session amortization;
- lazy/on-demand loading as its own comparison, not folded into eager A/B.

Primary outcomes: acceptance and hidden tests, missed callers, unsupported claims, unrelated changes, security/data-loss regressions, repair cycles, time to first passing patch, final wall time, inclusive tokens/cost/tools/errors.

Measure lifecycle phases without letting them replace normal-use evidence:

- startup for absent, eager-cold-daemon, eager-warm, lazy-unused, and lazy-first-activation;
- a completely new codebase from an empty cache;
- every advertised graph-build mode;
- incremental refresh, repeated-query, teardown, and cleanup latency.

For each relevant phase record wall time, CPU time/utilization, peak RSS, peak process count, cache/artifact bytes, files and LOC per second, node/edge counts, skips/failures/coverage, daemon readiness, and first useful query latency. Attribute the full process tree; if measurement misses detached workers, quarantine the attempt and rerun after fixing attribution.

### 3. Deterministic advertised-capability conformance

Use controlled fixtures when a real repository cannot provide exact ground truth. Cover, when advertised by the tested release:

- graph schema and custom query language;
- inbound/outbound call and data-flow tracing;
- semantic/BM25/structural/code search;
- HTTP, gRPC, GraphQL, tRPC, event/channel, and cross-service links;
- cross-repository edges and summaries;
- Docker, Kubernetes, Kustomize, and other infrastructure nodes;
- ADR create/read/update/delete lifecycle;
- runtime trace ingestion;
- team-shared graph artifact import/update;
- auto-index, watcher, daemon coordination, concurrent clients, cleanup/deletion;
- representative supported languages and package-resolution styles.

Deterministic backend checks need not be repeated seven times unless noisy. Report them separately from agent quality so conformance does not inflate the production A/B result.

## Repository shape

Use at least one genuinely large real monorepo with a recorded immutable commit, clean-state assertions, multiple packages/services, and runnable focused tests. Add small synthetic fixtures only for specialized graph relationships or lifecycle faults that need exact hidden truth. Never call a tiny fixture a scale benchmark.

## Timing isolation and safe parallelism

Keep canonical timed phases serial: production A/B parents, startup/RSS, cold indexing, incremental refresh, and acceptance-test execution must never overlap. Concurrent cells contaminate provider latency, CPU/RSS, filesystem cache, test duration, and shared daemon/cache coordination; simultaneous retain/remove arms are especially asymmetric because the removed arm competes with the retained arm's runtime. Assert non-overlap from recorded start/finish timestamps.

Parallelize only after timed collection stops: independent mechanical scoring, hidden-test replay, blinded review, report audits, checksum validation, and non-timed fixture preparation. If parallel trials are explored, label their wall/resource metrics invalid and exclude them from the canonical verdict unless each balanced block runs on a separate comparable host and host effects are modeled explicitly.

## Host-load provenance and late contamination

Freeze the host-load policy before trial 1: either require a clean host or deliberately benchmark the normally loaded production host. Capture the whole-host process/CPU snapshot—not just benchmark-owned processes—before every timed phase. Record long-lived workloads, start times, CPU/RSS, and whether they predate collection.

If unrelated load is discovered late, never silently reinterpret or overwrite the run:

1. Stop subsequent timed phases and preserve the original result set plus a machine-readable contamination record.
2. Quarantine it under the stricter frozen protocol and hash that quarantine.
3. Ask the user whether to rerun clean, salvage only non-host-sensitive dimensions, or accept it explicitly as a loaded-host benchmark.
4. If loaded-host acceptance is chosen, add an immutable user-decision/manifest addendum, restore results by copy rather than rewriting quarantine, and label every wall/startup/index/RSS/CPU number as loaded-host—not a clean-host causal estimate.
5. Re-run validators and artifact hashes against the accepted copies.

Do not assume correctness, tokens, cost, or timing are all equally contaminated. Classify each metric explicitly, preserving uncertainty. A stable background workload can be representative production context, but post-hoc acceptance weakens causal timing claims and must remain visible in the verdict.

SQLite/config byte hashes can change from page layout or benign writes while logical rows remain identical. Preserve the mismatch, compare a canonical logical dump, and do not destructively overwrite live state unless an exact original is available and ownership is certain.

## Executable-oracle integrity

A test passes only when its process exits `0` within a prevalidated timeout. Never infer success from log text after killing a process or treat `timed_out_after_pass` as passing. Establish each command's clean-baseline runtime first, then choose a bounded timeout with headroom; record timeout as failure. Launch agent and test commands in their own process groups and terminate the whole group in `finally` so interrupted cells cannot leave orphan workers.

When instrumentation, attribution, isolation, or oracle logic is wrong, stop before more cells run. Move every affected raw artifact under an explicit excluded-attempts/quarantine directory with its reason, fix the shared harness root cause, rerun a representative smoke cell, and resume only from independently validated unique cells. Never overwrite or silently replace an invalid attempt.

## Long-running supervision

For multi-hour matrices, supervise progress independently of the writer. Poll at a bounded cadence such as 10 minutes and verify the tmux/session pane, benchmark runner, newest artifact timestamps, completed-versus-expected unique cells, nonzero exits, test timeouts, serial non-overlap, daemon/cache isolation, orphan process groups, disk/memory pressure, and clean worktree teardown. A monitor process exiting successfully does not prove the benchmark finished; check the pane and authoritative run ledger.

Keep one writer. The supervisor should send precise corrections to the existing agent rather than launch another benchmark or edit concurrently. On a clear accuracy fault, stop the affected phase, quarantine partial/invalid attempts with a reason, fix the shared harness, smoke-test, and resume from validated unique cells. Healthy checks should be terse; never perturb a timed phase merely to inspect it.

## Freeze before expensive execution

Save and validate:

- repository choice, commit, size/language/package inventory, and test feasibility;
- exact variants and machine-readable config/tool diffs;
- requirement-to-cell-to-tool coverage manifest;
- workload matrix and exact expected run count;
- visible acceptance criteria and hidden tests;
- smoke result for one representative cell;
- estimated time, cost, disk, and peak memory.

Reject launch when any advertised requirement lacks a cell or explicit exclusion.

## Completion gate

A validator can prove produced artifacts are internally consistent while still missing an explicitly requested suite. Before declaring completion, reconcile the final artifact inventory back to the frozen requirement matrix—not just the run ledger. Assert at minimum:

- every production, lazy, conformance, startup, indexing, and cleanup cell is present or explicitly marked impossible;
- repeat counts and variant counts match the frozen matrix;
- every requested metric has actual observations, not only a report placeholder;
- startup includes all promised absent/eager-cold/eager-warm/lazy-unused/lazy-activation modes;
- raw, inclusive, hidden-test, blind-review, and checksum validators passed on the final accepted result root;
- benchmark processes/worktrees/caches are cleaned and live config is logically restored.

If a late audit finds a missing requested suite, resume only that suite and update validation/hashes/report; do not call the benchmark complete merely because the main A/B matrix finished.

## Decision boundary

Report eager retain/remove, lazy loading, and direct conformance independently. A useful direct tool can still lose as an eager default. Conversely, a read-only efficiency win does not prove equivalence for edits, stale graphs, refactors, large monorepos, or long sessions.
