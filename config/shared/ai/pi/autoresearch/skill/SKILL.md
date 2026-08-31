---
name: pi-autoresearch
description: Run a bounded optimization loop in a disposable Git worktree or JJ workspace
---

# Pi Autoresearch

Optimize one measurable target through finite, reversible experiments.

## Setup

1. Confirm the goal, primary metric, direction, files in scope, constraints, and authoritative correctness checks.
2. The extension has already verified a supported platform and either a clean linked Git worktree on an `autoresearch/*` branch or an empty dedicated JJ workspace named `autoresearch-*`. When invoked from a clean primary Git checkout or normal JJ workspace, `/autoresearch` creates a uniquely named sibling worktree/workspace and switches Pi into a named session there before loading this skill. Never switch branches or workspaces, change repositories, add hooks, push, or finalize automatically.
3. Create and commit with the active VCS:
   - `.auto/prompt.md`: goal, metric, files in scope, off-limits paths, constraints, benchmark method, and attempted ideas.
   - `.auto/config.json`: `maxIterations` from 1 through 20, `metricName`, and `direction` (`lower` or `higher`).
   - Linux/macOS: executable `.auto/measure.sh` and `.auto/checks.sh` using `set -euo pipefail`.
   - Windows: `.auto/measure.ps1` and `.auto/checks.ps1` using `$ErrorActionPreference = 'Stop'`.
   - The measure script must output `METRIC <metricName>=<number>`; the checks script must run the smallest authoritative correctness checks.
4. If a Git setup commit fails because signing is locked, stop and ask the user to run `printf test | gpg --clearsign >/dev/null`. For JJ, report the configured signing failure. Never disable signing.

## Commands

- `/autoresearch status`: show VCS, workspace, revision, iteration budget, best metric, last status, and pending-run state.
- `/autoresearch off`: disable autoresearch tools without removing the workspace.
- `/autoresearch cleanup`: after all changes are committed and the worktree is clean, confirm, return to the automatically recorded parent session, and remove only the worktree/workspace. Git branches and JJ commits remain available.

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

For noisy workloads, use repeated alternating baseline/candidate trials and keep only improvements beyond observed noise. Correctness and explicit constraints override the primary metric. Never edit unrelated files, call raw VCS cleanup commands, create `.auto/hooks`, push, or continue past `maxIterations`.
