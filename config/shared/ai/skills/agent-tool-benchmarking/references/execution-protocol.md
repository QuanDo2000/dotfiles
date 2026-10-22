# Benchmark execution protocol

Read before designing or collecting trials. Paths below are relative to this reference directory.

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

Before paid collection, exercise the actual native tool path without inference: verify prompt/file/terminal workspace agreement, enforce filesystem and subprocess-environment isolation, and prove legitimate edits/tests plus synthetic escape attempts. Setting cwd alone is not containment. Keep provider authentication outside model-selected tools; use the client's credential-opaque login path when authorized rather than copying credentials. See `native-provider-tool-containment.md` for the tested boundary and accounting recipe.

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
12. Make long serial matrices resumable without weakening provenance. Persist completed cells atomically, classify failed attempts by whether provider work began, and resume from the first missing canonical position. See `resumable-serial-matrices.md`.

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

Resolve authentication during preflight, before building a provider-backed matrix. An isolated agent root often lacks the live login even when the ordinary client works; do not discover this only after the harness is complete. Prefer a dedicated benchmark credential. If none exists, stop and obtain explicit user approval before copying live authentication. For an approved copy: copy only the minimum standard auth files into a dedicated mode-700 directory with mode-600 files; never open, parse, print, hash, diff, log, archive, or include credential bytes in reports/checksums; preserve live auth byte-for-byte and metadata; delete every copy on success, failure, cancellation, and budget-stop paths; verify cleanup by existence checks only. Before a long serial run, determine whether OAuth uses rotating refresh tokens. A fresh per-cell copy can consume its refresh token and leave the unchanged live source stale; with separate explicit approval, use one isolated auth chain for the uninterrupted run, atomically carry only the refreshed credential file between cells, and still clean it on every terminal path. Treat authentication as transport, not a benchmark variant. See `rotating-oauth-benchmark-auth.md`.

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

See `production-additive-ab.md` for a reusable production-shaped A/B recipe and report checklist. For conservative per-workload cost projection, Codex cumulative-token parsing, provider-failure quarantine, and writing a durable budget-stop artifact before exit, see `budget-gated-codex-calibration.md`. For rotating-refresh OAuth isolation across serial cells, see `rotating-oauth-benchmark-auth.md`. For a validated 84-cell native Codex multi-agent natural-adoption example, including restart recovery and final-audit traps, see `codex-native-multi-agent-natural-ab.md`. For isolated Hermes `delegate_task` A/B configuration, SQLite parent-plus-child accounting, and cost-rollup rules, see `hermes-native-delegation-ab.md`.
