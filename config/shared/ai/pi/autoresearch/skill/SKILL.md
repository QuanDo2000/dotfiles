---
name: pi-autoresearch
description: Run a bounded optimization loop in a disposable linked Git worktree
---

# Pi Autoresearch

Optimize one measurable target through finite, reversible experiments.

## Setup

1. Confirm the goal, primary metric, direction, files in scope, constraints, and authoritative correctness checks.
2. The extension has already verified Linux, a clean linked worktree, and an `autoresearch/*` branch. Never switch branches, change repositories, add hooks, push, or finalize automatically.
3. Create and commit:
   - `.auto/prompt.md`: goal, metric, files in scope, off-limits paths, constraints, benchmark method, and attempted ideas.
   - `.auto/config.json`: `maxIterations` from 1 through 20, `metricName`, and `direction` (`lower` or `higher`).
   - `.auto/measure.sh`: executable, `set -euo pipefail`, and output `METRIC <metricName>=<number>`.
   - `.auto/checks.sh`: executable, `set -euo pipefail`, and run the smallest authoritative correctness checks.
4. If the setup commit fails because signing is locked, stop and ask the user to run `printf test | gpg --clearsign >/dev/null`. Never disable signing.

## Loop

1. Run `autoresearch_run` for the baseline, then `autoresearch_log` with `status: baseline`. If the initial benchmark crashes, log `crash`, repair and commit only the `.auto` setup, then retry the baseline.
2. Make one small in-scope change.
3. Run `autoresearch_run`.
4. Use `autoresearch_log` exactly once:
   - `keep`: only for a passing benchmark, passing checks, and demonstrated improvement.
   - `discard`: for a valid but unimproved result; the tool reverts the change.
   - `checks_failed`: when the benchmark ran but correctness checks failed; the tool reverts the change.
   - `crash`: for a failed benchmark; the tool reverts the change.
5. Update `.auto/prompt.md` only with durable findings, then continue until the configured limit, user interruption, or no safe useful ideas remain.

For noisy workloads, use repeated alternating baseline/candidate trials and keep only improvements beyond observed noise. Correctness and explicit constraints override the primary metric. Never edit unrelated files, call raw Git cleanup commands, create `.auto/hooks`, push, or continue past `maxIterations`.
