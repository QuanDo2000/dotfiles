# Delegation Timeout Diagnosis

Use when a delegated batch times out or loses its final summary. Inspect only the relevant run, not broad session history.

1. Read its `manifest.json` and task logs under `$HERMES_HOME/cache/delegation/live/<delegation-id>/`.
2. Record start/end/status, last successful activity, API/tool counts, duplicates, and errors. Compare with resolved `delegation.child_timeout_seconds`, `delegation.max_iterations`, and reasoning configuration.
3. Distinguish fixed-duration termination despite progress (run deadline), silent provider request, blocked tool/subprocess, exhausted iterations, and owner-process loss. A parent wait ending is not child termination.
4. Salvage factual evidence and recover the same run where possible before launching replacement work. Separate useful evidence from a successful final handoff.

## Correct only the demonstrated cause

Narrow over-scoped work, precompute mechanical inventories, and reserve time/budget for a summary. Avoid repeated skill loads, duplicate large reads, guessed paths, and error loops.

For authorized interactive-policy changes, Hermes can use `delegation.child_timeout_seconds: 0` (no hard child cap), with heartbeat and iteration controls remaining separate. Verify the installed default before unsetting an override. Positive deadlines remain valid unattended cost controls; do not remove them automatically or merely raise them to hide wasted work.

## Verify

Run one bounded smoke child with 2–3 exact source files, a small call budget, no unrelated exploration, and a concise output contract. Confirm expected reads, scope, completed status, useful summary, and completion notification. A small smoke validates the handoff path, not reliability for every long-running task.
