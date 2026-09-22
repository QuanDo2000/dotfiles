# Production additive A/B recipe

Use this when the operational question is “what happens if we add this extension to our current agent setup?”

## Controlled variants

```text
A: current setup, unchanged
B: current setup + candidate enabled per process
```

Keep the same repository revision, settings, instructions, model, thinking level, workload prompt, and normal tool set. Do not disable extensions, skills, prompt templates, MCP, memory, or project context. Do not inject temporary chat instructions unless they already belong to the agent setup.

The candidate must use its normal deployment mode. If it can coexist with native tools, expose both and let the model choose naturally. Record candidate tool calls separately from registration/startup success.

## Run matrix

For each workload:

1. Run seven fresh-process A/B pairs.
2. Alternate pair order: `A,B`, then `B,A`.
3. Rotate workload order between rounds.
4. Save stdout/stderr and raw structured events per run.
5. Validate answers immediately against frozen ground truth.

Suggested workload classes:

- exact symbol or definition lookup;
- exact path/set lookup;
- exhaustive content inventory;
- repository architecture/flow understanding;
- one representative task from the user's real workflow.

## Report table

For each workload and aggregate, include:

```text
variant | wall median/mean/stddev/range | turns | calls by tool |
input | cache read | cache write | output | total | cost | correctness
```

Also report:

- paired A→B deltas for every trial;
- percentage differences;
- candidate selection rate;
- failed calls and missing final answers;
- startup latency/RSS;
- tokens and dollars saved per added second when B is slower.

## Interpretation

Answer these separately:

1. Does the candidate improve correctness or recall?
2. Does it save end-to-end time?
3. Does it save total prompt-accounted tokens and money?
4. Is it actually selected in normal coexistence?
5. Is the tradeoff worthwhile under the user's stated priority?

A candidate can be worthwhile when it is slightly slower but materially cheaper. Conversely, sub-millisecond backend gains do not matter if provider turns dominate.

## Preservation checks

Compare before/after state only for non-secret settings. Keep credential files opaque: do not read, copy, hash, diff, or print them. Use isolated configuration and the runtime's existing credential interface; report that credential-content preservation was not independently inspected. Snapshot repository status before and after and preserve pre-existing or concurrent changes; never clean the repository to satisfy this check. Remove only experiment-owned temporary package trees, native bindings, indexes, databases, and child processes, retaining the private report, redacted events, harness, validation output, and exact package metadata.
