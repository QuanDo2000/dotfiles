# Mutation A/B harness hardening

Use this when adapting an existing read-only agent/tool benchmark to executable code mutation.

## Minimal reliable pattern

- Keep the proven serial A/B runner, inclusive parent/child accounting, matrix assertions, and cleanup audits. Replace prompts and add disposable mutable worktrees; do not build a second framework.
- Freeze the source revision, current settings/config hashes, and the package path resolved from the candidate entry in `settings.json`. Do not infer the loaded version from a stale convenience install such as `npm/node_modules`.
- Variant A retains the candidate package and its settings. Variant B removes only that package entry and candidate-specific top-level settings. Assert the exact delta.
- Put hidden graders outside candidate worktrees. Verify every seeded parent fails its hidden grader before spending provider calls.
- Preserve pilot artifacts before resetting for the full matrix. Freeze a conservative projection using the larger of pilot extrapolation and prior comparable workload evidence, then enforce hard cost and wall ceilings after every cell.

## Immutable package trees

Locked extension closures may contain read-only directories and symlinks into the Nix store. Blind `shutil.rmtree(..., ignore_errors=True)` can leave a partial cell that breaks the next run.

Before deletion:
1. Terminate processes whose isolated-cell path appears in their environment.
2. Walk the owned copied tree without following symlinks.
3. Make owned non-symlink directories/files writable.
4. Run strict `shutil.rmtree`; never suppress cleanup errors.
5. Assert the cell root and transient credentials are gone.

Do not `chmod` symlink targets: this can dereference into immutable storage and fail with `EPERM`.

## Coverage proof

A source-marker inventory proves advertised capability exists, not that it works. Separate evidence:

- static/config assertions: enabled and disabled roles, effective model/thinking/tool routing, model scope, async/artifact settings, and limits;
- upstream package tests: implementation paths, run in an isolated repository/config environment;
- runtime smoke: only use cases/settings not naturally exercised by the production A/B matrix.

Do not claim all use cases tested from marker scans alone. Add a small explicit orchestration supplement only for measured gaps; avoid a full role × setting × workflow cross-product.

## Package-test isolation

Repository tests can inherit user Git signing and shared temporary state. Disable signing only for the test process using `GIT_CONFIG_COUNT` variables. If tests share observer/session state, use the package's documented isolation hook and serial test concurrency. Treat unresolved upstream-suite failures as supplemental failures, not as passed coverage and not as a reason to invalidate independently verified production cells.