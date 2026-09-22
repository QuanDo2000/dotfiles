# Budget-gated Codex calibration and recovery

Use this pattern for a native-feature A/B whose full matrix may exceed a fixed spend ceiling.

## Calibration gate

1. Run one quarantined A/B pair for every substantive workload class. Do not extrapolate the full matrix from one cheap workload.
2. Count every provider-started attempt, including OOMs, capacity errors, and replaced cells.
3. Project conservatively per workload:

   ```text
   projected_total = excluded_attempt_cost
                   + valid_pilot_cost
                   + Σ(max(A_pilot_cost, B_pilot_cost) × canonical_cells_for_workload)
   ```

4. Write the calibration artifact atomically **before** raising or exiting on a budget stop. Include `status=BUDGET_STOP`, ceiling, pilot IDs, excluded cost, per-workload maxima, projection, and canonical cells started.
5. If the projection exceeds the approved ceiling, launch zero canonical cells. A pilot result is exploratory and must not drive a production configuration change when the preregistration required seven trials.

## Rolling canonical gate

Before every canonical cell, recompute rather than reusing the frozen pilot projection:

```text
rolling_projection = all_excluded_attempt_cost
                   + valid_pilot_cost
                   + completed_canonical_cost
                   + Σ(max(pilot_workload_max, observed_canonical_workload_max)
                       × remaining_cells_for_workload)
```

Canonical cells can be materially more expensive than pilots. Persist a machine-readable gate artifact before raising, containing the observed maxima, completed count, current excluded cost, ceiling, and projection. A fixed-pilot-max gate can remain under the nominal ceiling while its real completion projection has already crossed it.

A raised ceiling is a new authorization boundary: record the disclosed projection and already incurred cost in a post-registration addendum, change the exact approval marker, rerun structural/cleanup checks, and resume only missing canonical IDs. Do not rewrite the original preregistration or silently treat “continue” as unlimited spend.

## Provider and resource failures

- A provider capacity/rate-limit exit is invalid transport, not a correctness failure. Quarantine it, retain its usage, and retry the same task/variant in a fresh session.
- Test the commands the agent is likely to run—not just the hidden grader—inside the same cgroup/resource envelope used by canonical workers. A successful foreground check may have a larger memory allowance.
- Prefer documented package-scoped commands and serial test workers. If a required checked-in generated artifact can be updated directly but its generator cannot fit, apply the same explicit constraint to both variants and record a pre-registration addendum.
- After an externally killed worker, first copy the isolated session tree to quarantine while excluding authentication, then delete the credential home and worktree. If raw rollout data was lost, disclose that the partial cost record cannot be independently reparsed; never promote it to quality evidence.

## Codex JSONL accounting

- `event_msg.token_count.info.total_token_usage` is cumulative within a rollout. Use the **last** value from each parent/child rollout, then sum rollouts; do not sum every token event.
- Count `custom_tool_call` as a tool invocation; Codex tool calls are not necessarily labeled `function_call`.
- Count token-count events as provider turns when the client exposes no separate provider-call counter, and label that proxy explicitly.
- Preserve both `codex exec --json` stdout and the isolated rollout session files. Reparse valid cells from rollout files before reporting.
- Derive parent versus child threads from session metadata, then verify unique parent IDs and child-parent links.

## Interpretation

A workload-balanced one-pair pilot with zero natural delegation measures default-list adoption only. Report the zero selection and paired correctness, but keep the production configuration unchanged unless the predeclared confirmatory matrix completes or the user explicitly accepts exploratory evidence.
