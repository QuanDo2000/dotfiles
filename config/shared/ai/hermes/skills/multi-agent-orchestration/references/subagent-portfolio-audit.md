# Subagent Portfolio Audit

Use this after several days of real agent activity, before deleting roles or uninstalling delegation support.

## Evidence sources

Prefer structured local evidence over anecdotes:

- Parent transcripts: launch, list, status, wait, steer, stop, and completion-notification counts.
- Child transcripts: resolved role/model, start/end timestamps, API turns, tool calls/errors, final response, and output size.
- Runtime database: parent-child links, end reason, tokens/cache reads, tool/API counts.
- Managed configuration: effective role overrides, disabled flags, model routing, concurrency/spawn ceilings, timeout, and summary caps.

Count by role and model. Also compute:

- completed handoffs / child runs;
- role share of children;
- role share of child tools/output;
- waits and status/list calls per child;
- failed launches separately from owner/session-loss outcomes;
- duplicate review waves against an unchanged target.

Treat error-like text counters as heuristics unless the runtime marks the event as an error.

## Interpretation

- **High completion, low duplication:** role is useful.
- **High completion, dominant tool/output share:** role may be useful but overused; reduce fanout and prompt scope first.
- **Low use, unique capability:** keep as an explicit exception if its failure domain matters (for example, sole writer or high-stakes oracle).
- **Low use, overlapping capability:** reversibly disable.
- **Useful child evidence, missing final summary:** evidence utility is positive but handoff utility failed; fix lifecycle/durability rather than deleting the role.
- **Async launch followed immediately by wait:** no parallel benefit; use foreground or yield for completion.

Do not infer usefulness from role count alone. Reviewers naturally outnumber writers in review-heavy workflows, but several generic reviewers inspecting the same unchanged diff are duplicate work.

## Minimal retained portfolio

A practical default is:

- scout — local code/context discovery;
- researcher — external/primary-source research;
- worker — one mutation owner;
- reviewer — independent static review;
- oracle — rare high-risk decision consistency.

Aliases, generic delegates, planners, and context builders are removal candidates when the parent or retained roles already cover them. Disable first; delete only after a representative observation period and dependency check.

## Optimization order

1. One reviewer by default; second only for a distinct named risk.
2. Parent precomputes inventory/diff once and sends a compact evidence packet.
3. Remove acceptance schemas and validation-command requests from static reviewers.
4. Stop polling; rely on completion notification or one blocking wait only when same-turn synthesis requires it.
5. Route routine children to the normal child model; override upward only for explicit high-risk work.
6. Reduce active async/session ceilings; keep a larger per-workflow ceiling only when exceptional fanout is genuinely needed.
7. Cap returned summaries while preserving durable file artifacts for long evidence.
8. Re-measure before further cuts.

## Verified case shape (August 2026)

A two-week audit found 205 Pi child sessions. Reviewers were 138 children (67.3%) and 9,226 of 11,013 child tool calls (83.8%). Parents made 288 explicit waits for 205 children. Most children returned useful final responses, so the correct fix was not removing subagents: routine review moved to the normal child model, four overlapping roles were reversibly disabled, default reviewer fanout became one, and overlapping async/session ceilings were reduced.

A separate Hermes audit found 18 children; 15 closed normally and three lost their terminal handoff when the owner exited. Concurrency and inline-summary limits were reduced, while critical long work was routed toward durable artifacts/processes rather than hard child timeouts.

## Verification

After configuration changes:

1. Parse the effective config through the runtime or its CLI—not only the source template.
2. Confirm disabled roles are absent from discovery and retained roles resolve to intended models/tools.
3. Run the smallest existing configuration test.
4. Check source and live config independently when deployment is generated or symlinked.
5. Do not activate a broad configuration transaction when unrelated dirty changes would be included; apply a safe live structured update and leave the tracked source ready for the normal deployment path.
6. Record baseline and re-audit window; do not claim savings before new usage exists.
