# Delegation timeout diagnosis

Use this when a delegated batch reports `timeout` with no summary.

## Triage order

1. Read the batch `manifest.json` and each append-only task transcript under:

   ```text
   $HERMES_HOME/cache/delegation/live/<delegation-id>/task-<n>.log
   ```

2. Extract start/end times, final status, API-call count, tool-call count, duplicate exact calls, tool errors, and the timestamp of the last successful result.
3. Compare the duration against resolved policy:

   ```bash
   hermes config get delegation.child_timeout_seconds
   hermes config get delegation.max_iterations
   hermes config get delegation.reasoning_effort
   ```

4. Distinguish:
   - exact fixed-duration cutoff while activity continued → hard watchdog;
   - one long silent API request → provider/stale-call path;
   - one long tool call → tool timeout or blocked subprocess;
   - call count matching iteration limit → over-scoped child or missing summary reserve;
   - parent reset/process exit → non-durable ownership loss.
5. Salvage factual evidence from the transcript before launching replacement work.

## Proven watchdog signature

A real two-child audit showed:

| Child | Duration | API calls | Last successful activity |
|---|---:|---:|---|
| Runtime audit | 600.04 s | 17 | 23 s before termination |
| Algorithm audit | 600.12 s | 50 | 2 s before termination |

Both ended at the configured `child_timeout_seconds: 600`, despite active progress. One also reached 50 API calls, matching the configured iteration budget. The failure was not an unresponsive network request; it was an obsolete hard cutoff plus tasks too broad to reserve a summary turn.

## Minimal correction

For interactive reasoning children, remove the explicit hard cap and use the current default:

```bash
hermes config unset delegation.child_timeout_seconds
hermes config get delegation.child_timeout_seconds  # resolves to 0
```

Keep a positive cap only for unattended cost control. Do not raise it blindly when the child is wasteful; first narrow the lane, precompute mechanical inventories, and add stop/output criteria.

## Bounded smoke test

Dispatch one child that may read only 2–3 exact files, allows at most four file calls, forbids skills/search/repository exploration, and requests exactly four bullets. Verify:

- completed status;
- expected file calls only;
- no scope broadening;
- correct summary;
- completion notification delivered.

In the proven smoke test, the child completed in 21.88 seconds with three reads and two API calls.

## Efficiency signals

Count duplicate exact calls and error loops separately from useful evidence. Common waste patterns:

- reloading the same skills late in the run;
- rereading large files under ambiguous basenames such as `result.json`;
- broad searches across thousands of artifacts;
- invalid wildcard-as-regex queries;
- probing guessed paths before discovery;
- using an LLM child for mechanical counts suited to `execute_code`.

Rate the child on two axes:

- **Evidence utility:** did it discover grounded facts?
- **Handoff utility:** did it return a usable final result?

A missing summary makes handoff utility zero even when evidence utility is high.
