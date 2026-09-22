---
name: agent-tool-benchmarking
description: Use when A/B benchmarking an agent tool or extension.
version: 1.0.0
---

# Agent Tool Benchmarking

Benchmark whether adding, removing, or replacing an agent tool improves the real workflow. Preserve one controlled difference, measure end-to-end outcomes, and distinguish production-shaped results from isolated backend speed.

## Decide whether a benchmark is warranted

Before designing a matrix, ask whether the decision is already determined by capability inventory and the user's established workflow. If removing the candidate eliminates a unique capability the user regularly needs, and the proposed control is not feature-equivalent (for example, `curl` versus hosted web search), skip the expensive keep/remove A/B. Keep the dependency and run only cheap route, health, safety, or conformance probes when useful. Likewise, an unreferenced dependency with no caller may need a static dependency audit and removal—not a provider-backed benchmark. Reserve full A/B runs for uncertain marginal value, overlapping capabilities, or meaningful quality/cost tradeoffs.

## Close the decision and choose the next target

Translate the result only as far as its measured boundary. A negative natural-selection delegation result supports removing default encouragement or exposure; it does not support deleting explicit orchestration capability without the separate explicit-orchestration supplement. When authorized to apply the verdict, change the narrowest production policy, leave one focused regression assertion, deploy it through the owning configuration path, read back the live behavior, and inspect the final diff for unrelated mutable-config backflow.

After closing a benchmark, distinguish “no further action for this decision” from “no other benchmark targets.” If asked what is next, inventory completed reports and unresolved decision boundaries, then rank candidates by expected decision leverage. Prefer a policy or prompt ablation that affects every run over another expensive replication of an already-covered natural-selection question. State the concrete configuration decision each candidate could change; skip experiments whose outcome would not alter behavior.

## Choose the benchmark shape first

Use the user's requested question literally:

- **Production-shaped additive benchmark:** `current agent setup` versus `current agent setup + candidate`. This is the default when the user asks what happens if they add a tool to their setup.
- **Isolated tool benchmark:** restrict both sides to equivalent minimal tools to measure backend capability. Use only when explicitly requested or as a clearly labeled supplement.

Never present an isolated benchmark as evidence for the production setup. If both are useful, run and report them separately.

## Preserve the production baseline

For a production-shaped comparison, baseline A keeps the live setup intact:

- global and project instructions/context;
- current settings and packages;
- extensions, skills, prompt templates, MCP servers, and memory tools;
- default model and thinking level;
- normal tool availability.

Variant B must differ only by the candidate tool or extension. Enable it per process when possible; do not persist configuration merely to benchmark it. Use the candidate's normal additive mode, not a tools-only or replacement mode, unless that is how the user would actually deploy it.

Do not inject a chat-only persona, system prompt, or temporary instruction into benchmark children unless it is genuinely part of the target agent configuration. Identical artificial prompts can make an A/B comparison internally fair while answering the wrong operational question.

Capture a fresh runtime tool schema before provider-backed collection and reconcile it with every baseline claim. A static feature flag is not effective-state proof when the supposedly disabled tools remain registered or are selected. If an unrelated capability is equally present in both variants, the target contrast may remain usable, but relabel the baseline accurately and include that capability's calls, children, tokens, and cost.

## Pilot safety and subscription comparisons

Before paid collection, exercise the actual native tool path without inference: verify prompt/file/terminal workspace agreement, enforce filesystem and subprocess-environment isolation, and prove legitimate edits/tests plus synthetic escape attempts. Setting cwd alone is not containment. Keep provider authentication outside model-selected tools; use the client's credential-opaque login path when authorized rather than copying credentials. See `references/native-provider-tool-containment.md` for the tested boundary and accounting recipe.

Audit the first attempt before launching its counterpart, then audit the first pair before expanding the matrix. Require the intended workspace, substantive task execution, executable grading, scope/privacy checks and reconciled usage—not merely a successful process exit. Stop on harness-invalid execution; retain model correctness failures as scored outcomes when the harness is valid. Preserve excluded spend and original budget baselines when a retry is authorized.

For subscription comparisons, clarify full-allowance percentage points versus percentage of remaining allowance. Measure account-window deltas separately from token counts: cached input, uncached input, output and model weighting can reverse a total-token ranking. A rounded unchanged meter is inconclusive, not free usage. Do not spend more merely to move the meter; disclose concurrent account traffic and reporting lag. Distinguish an approved conservative early-stop guard from a provider-enforced cap. With one matched pair, report observations and keep the incumbent unless evidence supports changing it; an inconclusive allowance result does not establish either model's savings.

## Trial design

1. Record repository revision, package version/integrity, agent version, model, thinking level, and relevant configuration hashes.
2. Build current ground truth with authoritative repository commands or direct source inspection.
3. Use fresh no-session processes for each trial while preserving normal setup loading.
4. Alternate A/B launch order and rotate workload order.
5. For noisy provider-backed runs, use **seven trials per workload per variant** by default. Reduce only when cost is material and disclose it.
6. Let production variants choose naturally among all available tools. Do not force the candidate tool.
7. Include workloads spanning exact lookup, multi-file inventory, and repository understanding. Add realistic work from the user's normal workflow when available. For a removal ablation, exercise the dependency's actual feature class: architecture reconstruction, impact tracing, root-cause localization, and implementation planning for code-intelligence tools; cross-session recall for memory tools; diagnostics and repair for LSPs. Treat exact symbol/path checks as sanity cells, not substantive evidence that a specialized dependency is dispensable.
8. Before scoring, assert the complete matrix exists exactly once: `trials × workloads × variants`, with unique run/session IDs and no missing or duplicate cells. If the user changes the requested trial count, update this assertion before continuing and reject any report built from the old count.
9. Freeze the user-approved spend ceiling in the canonical preflight artifact. An inherited skill default, stale pilot gate, or adapter constant must never override the explicit ceiling in the current task. Compare the inclusive projection against that exact value before provider calls, and carry the same value through retries and the final report. During canonical execution, recompute the rolling projection before every cell using the larger of each workload's pilot maximum and all observed canonical costs, plus every excluded attempt accumulated since calibration. Persist the gate state before stopping. A canonical outlier can legitimately invalidate a passing pilot projection; treat that as an expected safe stop, not a failed harness. If the user raises the ceiling, preserve the original authorization unchanged, record a post-registration addendum with the new exact marker and completed spend, rerun the provider-free rolling gate, then resume from the first missing valid cell. Never reinterpret or overwrite the old approval.
10. Independently score correctness and audit calculations from raw event streams.
11. Treat a coverage-balanced suite as coverage, not a measured workload-frequency distribution. Report per-stratum effects first, then condition the operational verdict on the user's actual task frequency and priorities. If those are unknown and they could reverse the decision, make the recommendation conditional instead of categorical.
12. Make long serial matrices resumable without weakening provenance. Persist completed cells atomically, classify failed attempts by whether provider work began, and resume from the first missing canonical position. See `references/resumable-serial-matrices.md`.

### Subagent ablations

First classify the candidate as a third-party extension/package or a native client feature. For a native feature, A is the unchanged production client and B is the same client with only the documented feature switch disabled per process; do not invent package-removal work or custom roles that production does not use. Prove the A/B structural difference from fresh-session registered tool schemas before provider-backed collection.

For configurable subagent extensions, load `references/subagent-extension-coverage.md` before freezing the matrix; it separates one-time full surface coverage from repeated production A/B cells. For executable mutation harness cleanup, loaded-package resolution, hidden-grader seeding, and honest runtime-coverage proof, also load `references/mutation-ab-harness-hardening.md`.

When auditing prior adoption, parse structured tool-call events and their arguments. Raw substring search is only candidate discovery because prompts, documentation, and tool schemas can mention spawn/lifecycle names without an actual call. Do not use sessions from older client versions as proof of current runtime coverage.

A subagent benchmark must measure delegation as a system, not just the parent process:

- Preserve every child session JSONL/status before cleanup and include all child provider turns, cache/input/output tokens, cost, internal tool calls/results/errors, launch failures, and completion states. Parent wall time remains end-to-end time to parent settlement.
- Variant A keeps the full production subagent package, roles, instructions, and natural selection behavior. Variant B removes only that package plus the minimum references to tools/roles that no longer exist. Do not force A to delegate or forbid ordinary non-subagent tools.
- Include sanity controls plus broad substantive work where delegation could plausibly help: architecture reconstruction, impact tracing, root-cause localization, implementation planning, code/security review, CI diagnosis, test-gap analysis, and bounded inventory/refactor-risk analysis. Freeze source-grounded rubrics before execution and score blinded.
- Report delegation frequency, children per run, child success/failure, and the inclusive resource exchange rate. An unused subagent package proves overhead only; frequently selected delegation with tied correctness but much higher inclusive cost is actionable evidence.
- Score quality with paired per-cell pass deltas (A wins / B wins / ties across trial×workload pairs), not aggregate pass counts alone — matching aggregates can hide a per-cell tie behind workload mix. Extract role-level adoption from the parent JSONL (the `agent` argument of every subagent toolCall): a package where only scout/reviewer roles are ever selected while worker/oracle never fire is partially dead weight even when the package is occasionally used. A tied-quality + partial-adoption + large-overhead result supports removing the package from defaults while keeping an explicit path. See `references/pi-subagents-natural-mutation-verdict.md` for the verified 98-cell case.
- Separate **spawn requests** from lifecycle/management calls (`list`, `status`, `resume`, `interrupt`, `stop`) in usage totals. “50 subagent calls” is misleading when only 23 launched children and 27 managed them.
- A static role/config manifest proves availability, not runtime coverage. If the frozen requirements say every enabled role, model route, or tool restriction must be exercised, parse parent spawn arguments plus child session metadata and tool traces to prove each one actually ran. Keep the production A/B natural and add a separately labeled, pre-budgeted forced-role supplement for missing roles; do not mix those cells into natural-adoption quality or overhead. Never mark all-role coverage complete from documentation/config checks alone.
- Before startup/RSS or wall-sensitive trials, check for competing media scans, builds, and benchmark processes. Wait, isolate, or explicitly exclude contaminated host metrics; lowering an unrelated scanner's priority is not equivalent to a clean host for startup measurement.

## Required metrics

Report raw trials plus median, mean, range, standard deviation, and paired per-trial deltas for:

- end-to-end wall time;
- provider turns/messages;
- tool calls and results, broken down by tool name;
- provider input, cache-read, cache-write, output, and total tokens;
- cost;
- correctness, missing answers, and failed tool results;
- startup latency and RSS when the candidate adds runtime code.

Track whether the model actually selected the candidate. A tool that is registered but unused did not cause an observed workflow improvement.

### Memory-extension ablations

A default-on memory extension can affect every run without a visible memory-tool call. Separate and measure three exposure paths:

1. **Policy/context exposure:** fixed system-prompt policy text, prompt bytes/tokens, standing instructions, and recent-failure injection.
2. **Natural tool adoption:** memory search/write calls, returned context, errors, and whether recalled facts changed the answer or artifact.
3. **Persistence lifecycle:** startup/backfill, indexing, background review, session flush, database/RSS/process costs, and writes.

Do not interpret zero memory-tool calls as zero extension exposure. Compare enabled versus absent with identical unrelated instructions and project context, and report fixed prompt/context overhead separately from selected-tool overhead.

Use synthetic, source-grounded memory and session fixtures containing no real personal data or secrets. Include cross-session decision recall, durable preferences, environment/conventions, interruption continuity, stale/irrelevant-memory resistance, and normal tasks where memory should abstain. Score exact recall, provenance, harmful false recall, current-evidence precedence, artifact correctness, and abstention. Isolate the extension root and all stores per cell using the extension's supported agent-root/config override; never let a benchmark process write to live memory or session databases.

Before launching the matrix, inspect each candidate's actual path resolver and set every extension-specific store override; an agent-root override does not prove that a third-party extension follows it. Run one canary write, enumerate both the isolated root and every possible live default target, and reject the canary unless all created files are under the cell root. For compaction, require evidence that `estimatedTokensAfter < tokensBefore`, that the retained raw tail cannot contain all scored facts, and that recall depends on a non-empty/useful compressed state. A compaction event plus correct recall is insufficient when the raw tail survived. Fixed grace sleeps are calibration waits, not latency: wait on lifecycle events with a ceiling and report that wait separately.

Before benchmarking multiple extensions together, run an actual-client coexistence preflight in both load orders and inventory duplicate tool/command names. A mock loader or internal first-wins rule does not override client resource validation; if the released pair is rejected before provider start, mark it not loadable and do not manufacture metrics by silently renaming a tool. Treat any shimmed combination as a separately pinned candidate. See `references/memory-extension-compaction-and-isolation.md`.

If the user explicitly requests metrics after a safety blocker, preserve the blocker and stopping-rule violation in a post-registration addendum, keep the results out of the installation verdict unless explicitly waived, and retain all provider spend. See `references/memory-extension-compaction-and-isolation.md` for the validated isolation canary, pressure checks, quarantine, coexistence preflight, and recovery workflow. For the verified Pi Hermes Memory isolation boundary, see `references/pi-hermes-memory-ablation.md`.

### Web-access extension ablations

Map capabilities before choosing the control. Hosted search, URL fetching, document extraction, repository cloning, and video understanding are different surfaces; `curl` is a fetch fallback, not an equivalent search backend. If an extension reuses the active model provider's login to call hosted search, removing the extension still removes that search capability even though provider authentication remains.

Record the resolved runtime route, endpoint class, provider/model, fallback order, and whether credentials came from the agent registry or separate configuration—without exposing credential values. Probe the actual route rather than inferring it from package marketing. Keep provider-vs-provider tuning separate from the first keep/remove decision, and cover freshness, citation/source accuracy, extraction fidelity, failure/fallback behavior, SSRF/domain policy, startup/RSS/schema overhead, and natural selection.

### Zero-selection interpretation

A natural-selection matrix with `0/N` candidate calls is still useful, but for a narrower decision:

- It measures **default-list adoption/exposure**, not the candidate's utility when invoked.
- Across a substantial representative matrix, zero selection plus tied correctness is operational evidence that the candidate does not earn default exposure. For a default-configuration decision, prefer removing it while retaining an explicit/on-demand path.
- Do not treat stochastic wall/token/call differences between no-call variants as evidence that the candidate itself helped or hurt task execution.
- Do not write “no evidence supports removal” merely because forced-use utility was unmeasured. State both conclusions: natural use was absent; forced-use utility remains unknown.
- When useful, report the exact one-sided binomial upper bound for the per-run selection rate (for `0/N` at 95% confidence: `1 - 0.05^(1/N)`).
- If utility matters independently, run a separately labeled forced-use or discoverability supplement; never mix it into the natural production matrix.
- Inspect the activation model before prescribing code changes. A globally imported extension that disables its tools at `session_start` and contributes zero active schema until an explicit command is already runtime-on-demand. Compare residual import latency/RSS with the cross-platform launcher and deployment complexity of relocating it; when the residual is negligible, no code change may be the smallest correct result. Remove only suggestion policy when the intended behavior is strictly user-invoked.

For bounded experiment-loop extensions, load `references/autoresearch-extension-ablation.md` for a Git/JJ matrix, forced-use evidence, child accounting, and activation-state interpretation.

When one resource improves while another regresses, quantify the exchange rate:

- tokens saved per added second;
- cost saved per added second;
- seconds saved per additional token/cost when time improves instead.

Interpret the result using the user's stated priority. Do not reject a candidate solely for a small latency or complexity penalty when token cost is the user's dominant concern.

## Prompt and cache accounting

Provider token schemas differ. Preserve all fields, inspect their semantics from raw events, and make overlap explicit:

- If `input` excludes cache activity: `prompt-accounted = input + cache_read + cache_write`; `total = prompt-accounted + output`.
- If `input` already includes cached tokens, as in Codex cumulative usage: `uncached = input - cached_input`; `total = input + output`. Never add `cached_input` to `input` again.

Add a verifier assertion for the chosen relationship and use the same formula in summaries, paired deltas, and cost calculations. Repeated system instructions compound across provider turns even when cached. Separate byte size from provider token count. A shorter output is not a total-token saving if repeated prompt context dominates.

## Removal ablations: prove the decision boundary

A removal result is only as broad as the workflows exercised. State that boundary explicitly instead of promoting a read-only result into a universal claim.

For **code-intelligence/index tools**, a strong read-only suite covers architecture reconstruction, impact tracing, root-cause localization, and implementation planning, and must prove the candidate was selected. Before claiming equivalence for implementation work, add separate cells for edits plus incremental change detection, cold indexing, stale/partial indexes, refactors with caller preservation, long-lived-session amortization, and lazy/on-demand loading. A warm copied graph with fresh no-session parents supports an eager-loading decision, not universal removal.

For a comprehensive decision, use a genuinely large pinned monorepo and real disposable-worktree edits. Freeze at least six normal warm workflows spanning architecture/impact, root-cause fix, caller-preserving refactor, multi-package change, regression-test repair, and security/data validation. These routine workflows drive the primary verdict (about 90% decision weight). Startup, empty-cache indexing, graph-build modes, specialized conformance, and cleanup remain separately reported lifecycle metrics (about 10% unless a safety or reliability failure is catastrophic); do not let one-time setup dominate routine-use quality.

Prove the tested version boundary before trial 1: compare the installed binary version and actual registered tool schemas with the latest published immutable release and its tagged documentation. Pin release/tag commits and record discrepancies with current unreleased source; never silently benchmark a tool present only on `main` as part of the released product.

For **subagent/orchestration tools**, separate two suites:

1. **Natural mutation A/B:** identical outcome prompts that do not force delegation. Use isolated disposable worktrees; score executable patches with acceptance tests, hidden regressions, scope control, security/data-loss checks, repair cycles, wall time, and inclusive parent/child usage.
2. **Explicit orchestration supplement:** parallel research lanes, one writer plus independent reviewer, isolated worktree integration, background/resume, and council/advisor flows. Report this separately because a no-subagent variant can work sequentially but cannot preserve the same orchestration capability.

Do not combine removal of two candidates in one variant. If a mutation benchmark exposes a graph-shaped gap after removing an eager code-index tool, benchmark lazy/on-demand loading separately.

For agent-side LSP extensions, use `references/lsp-extension-ablation.md` to cover natural mutation work, provider-free schema/failure conformance, configured-language runtime proof, per-call server lifecycle costs, and native-checker comparison.

For package and capability substitutions, use `references/dependency-substitution-parity.md` to compare release freshness, cross-platform ownership, rule-level parity, and uniquely reclaimable Nix closure rather than headline package size.

See `references/removal-ablation-coverage.md` for reusable workload matrices and acceptance criteria. For a comprehensive code-intelligence ablation covering large monorepos, edits, lifecycle behavior, lazy loading, and every advertised capability, use `references/code-intelligence-comprehensive-ab.md`.

## Cross-client replication and pilots

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

See `references/cross-client-pilots.md` for the reduced-matrix evidence and interpretation checklist. See `references/codex-cross-client-benchmarks.md` for the validated Codex adapter, accounting, live-state audit, and support-policy pitfalls.

## Verification and cleanup

Before reporting completion:

- reconcile the final artifact inventory against every frozen/user-requested suite and metric; an internally valid partial result is not complete;
- treat a zero-exit matrix process as **collection complete**, not benchmark complete. Run one explicit finalizer that writes the post-last-cell budget state, final summary, human report, audit, and then checksums last; make the verifier fail clearly when any required artifact is missing. A budget snapshot written only before each cell otherwise ends at `N-1`, and a per-cell summarizer may never create the report;
- rerun calculation validators against raw results; copied harnesses may contain stale validators from another suite, so inspect every retained validator for the current workload names, matrix size, result schema, artifact paths, token-overlap formula, and **current approved ceiling** before treating it as evidence. Read the ceiling from the canonical approval/status artifact rather than retaining a historical literal in the verifier;
- distinguish execution validity from scored correctness: provider exit/transport failure, missing telemetry, or an invalid-execution flag invalidates a cell; a deterministic grader's nonzero exit may be the legitimate recorded correctness failure and must still remain in the matrix. Assert the grader record and result record agree;
- after any quarantined-cell replacement, regenerate every dependent summary, blind score, report, consistency audit, and checksum from the final retained rows. Add a machine-readable report-versus-summary check; include preserved raw event streams in the manifest and generate checksums last. Never trust a worker's final prose as proof that stale pre-replacement aggregates were refreshed;
- compare only allowlisted non-secret configuration hashes and, when authorized, logical database contents when SQLite byte hashes differ; never hash credentials;
- compare repository status with the initial snapshot, preserve pre-existing/concurrent changes, and run `git diff --check` on the owned diff;
- remove only experiment-owned temporary packages, native binaries, indexes, and databases;
- preserve the report, harness, raw JSONL, summaries, excluded-attempt provenance, and audit output;
- state exactly what remained unverified.

If unrelated host load is discovered after collection, preserve the stricter-protocol quarantine. When the load has an exact bounded window, compare it against each cell's recorded `launch_started`/`launch_finished` timestamps—not an estimated start inferred from neighboring completion times or setup gaps. Quarantine and rerun only cells with an actual interval intersection, count their provider work against the existing approved gate, and record the incident. Require an explicit user decision before salvaging contaminated dimensions, relabeling timing, expanding spend, or accepting loaded-host results. Never relabel clean-host timing post hoc without a visible manifest/report addendum.

Resolve authentication during preflight, before building a provider-backed matrix. An isolated agent root often lacks the live login even when the ordinary client works; do not discover this only after the harness is complete. Prefer a dedicated benchmark credential. If none exists, stop and obtain explicit user approval before copying live authentication. For an approved copy: copy only the minimum standard auth files into a dedicated mode-700 directory with mode-600 files; never open, parse, print, hash, diff, log, archive, or include credential bytes in reports/checksums; preserve live auth byte-for-byte and metadata; delete every copy on success, failure, cancellation, and budget-stop paths; verify cleanup by existence checks only. Before a long serial run, determine whether OAuth uses rotating refresh tokens. A fresh per-cell copy can consume its refresh token and leave the unchanged live source stale; with separate explicit approval, use one isolated auth chain for the uninterrupted run, atomically carry only the refreshed credential file between cells, and still clean it on every terminal path. Treat authentication as transport, not a benchmark variant. See `references/rotating-oauth-benchmark-auth.md`.

Never edit live credentials or persist candidate configuration for a benchmark. Isolation applies to the orchestrator as well as child processes. Freeze an explicit allowlist of readable live sources before orchestration; if the protocol says no live memory/session reads, do not call `memory_search` or `session_search` merely to find prior harnesses. Do not call live mutation tools to record benchmark state. Store notes under the benchmark artifact root. Never commit or push unless explicitly requested.

## Pitfalls

- Treat resource-heavy commands the agent may choose as part of provider preflight, not only hidden-grader commands. In large monorepos, repository guidance can lead an agent to run workspace-wide tests, builds, or generated-artifact jobs even when the frozen task is narrow. Before provider calls, inspect those likely commands, replace equivalent broad work with documented package-scoped forms, force serial test workers when the execution cgroup is bounded, and run the exact scoped commands offline **under the same cgroup/resource envelope as canonical cells**; a foreground preflight with a larger memory allowance does not validate a background worker. If even the package-scoped generator cannot fit, preserve the required checked-in artifact update but explicitly forbid generator execution for both variants. If a provider-started attempt still OOMs, quarantine it, count partial spend, clean credentials/worktrees, document the symmetric prompt amendment, and rerun under a fresh cell ID or explicit replacement provenance.
- Treat provider-capacity/rate-limit exits as invalid transport attempts, not correctness outcomes. Quarantine the complete attempt, count its emitted usage, verify credential/worktree cleanup, and retry the same cell from a fresh session without changing its variant or task. Do not silently resume a partially completed patch.
- Drain child stdout and stderr while the process runs. Do not poll/wait for exit and only then read captured pipes: verbose Pi JSONL can fill the OS pipe buffer and deadlock an otherwise healthy serial matrix. Use `communicate()`/async readers or redirect each stream directly to a per-cell file, then parse after settlement. Quarantine every provider-started attempt from a deadlocked harness, retain its spend in inclusive accounting, and reserve the full preflight allowance when raw usage is unrecoverable.
- Disabling all current resources answers “which search backend is better,” not “should I add this to my setup.”
- Forcing candidate-only tools hides coexistence, selection, and fallback behavior.
- Three trials expose large effects but are weak for noisy model/provider variance; seven is the production default.
- Aggregate medians can hide workload-specific regressions. Always retain per-workload results.
- Cross-run comparisons are observational when provider latency/cache cannot be reset. Prefer interleaved A/B trials and paired deltas.
- A faster backend can still lose end to end because model turns dominate.

See `references/production-additive-ab.md` for a reusable production-shaped A/B recipe and report checklist. For conservative per-workload cost projection, Codex cumulative-token parsing, provider-failure quarantine, and writing a durable budget-stop artifact before exit, see `references/budget-gated-codex-calibration.md`. For rotating-refresh OAuth isolation across serial cells, see `references/rotating-oauth-benchmark-auth.md`. For a validated 84-cell native Codex multi-agent natural-adoption example, including restart recovery and final-audit traps, see `references/codex-native-multi-agent-natural-ab.md`. For isolated Hermes `delegate_task` A/B configuration, SQLite parent-plus-child accounting, and cost-rollup rules, see `references/hermes-native-delegation-ab.md`.
