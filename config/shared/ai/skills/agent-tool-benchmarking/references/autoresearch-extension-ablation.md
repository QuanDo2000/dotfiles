# Autoresearch extension ablation

Use this reference when evaluating a bounded experiment-loop extension that is imported globally but activated only by an explicit command.

## Fair comparison

- A keeps the production extension, its discoverable skill, and its suggestion policy.
- B removes the extension plus only policy/skill references to unavailable tools.
- Eligible prompts explicitly authorize the same bounded number of experiments for both variants without naming or forcing the extension; B may iterate manually.
- Include objective-metric strata such as deterministic runtime, artifact size/allocation, hidden-case quality, and both Git and JJ workspaces.
- Include controls where repeated experiments are unnecessary and where the requested metric is unsafe, destructive, or ill-defined; correct behavior is abstention.
- Use seven paired trials per workload, deterministic local metrics, hidden correctness checks, fixed seeds, and identical native commands.
- If natural adoption is zero, add a separately labeled forced-use supplement for Git and JJ. Never mix forced-use quality into canonical wins.

## Activation-state interpretation

Inspect activation mechanics before recommending deployment changes. A globally imported extension can already be **runtime-on-demand** when it disables its tools at `session_start` and exposes zero active schema bytes until an explicit command enables them.

Report separately:

1. import/startup and idle RSS;
2. inactive registered schema and discoverable policy/skill bytes;
3. active tool use, child sessions, experiment progression, and provider cost.

Zero natural selection with tied quality rejects a claim that the extension earns active/default exposure, but it does not automatically justify moving files or adding launch wrappers. Compare residual import overhead with the maintenance and cross-platform complexity of a true optional loader. When tools are already explicitly activated and measured residual overhead is negligible, **no code change** can be the smallest correct outcome. Remove only the suggestion policy if the desired behavior is “user must invoke; never suggest.”

## Forced-use evidence

Capture parent and replacement/child session JSONL before cleanup. Score baseline/keep/discard progression, authoritative checks, final hidden checks, in-scope patch, retained best metric, discarded-change rollback, and workspace cleanup. Account for parent plus child provider turns, cache/input/output tokens, cost, tool errors, and end-to-end wall time.

Some RPC runs may omit a final settled event after a terminal extension tool result. If the tool emits an authoritative `done=true` terminal result and the process exits cleanly, wall time may end there only when disclosed as a protocol limitation; do not fabricate a settlement event.

## Verified decision pattern

A representative 84-cell run found 0/42 natural runtime adoption and no attributable canonical quality gain, while explicit Git and JJ forced-use runs both retained correct measured improvements. The operational result was: preserve explicit utility, avoid claiming default-use value, and recognize that an extension already disabled at session start may need no deployment change.
