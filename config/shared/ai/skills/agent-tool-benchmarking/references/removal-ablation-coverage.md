# Removal-ablation coverage matrices

Use this reference after a read-only benchmark recommends removing an agent capability. It prevents a narrow efficiency result from becoming a universal claim.

## Code-intelligence/index tools

### Core read-only suite

- architecture reconstruction;
- cross-file impact tracing;
- root-cause localization;
- implementation planning;
- exact symbol/path sanity controls.

Require natural candidate selection and source-grounded blind scoring. This suite can justify removing **eager loading** when quality ties and startup/provider overhead is material.

### Uncovered-until-tested cells

| Cell | Required evidence |
|---|---|
| mutation-aware graph | edit a disposable worktree, refresh incrementally, and detect missed callers |
| refactor preservation | rename/move/change an API and pass hidden caller/compatibility tests |
| cold lifecycle | index from empty state; record build time, CPU, RSS, disk, and first-answer quality |
| stale/partial index | rename/delete files without a full rebuild; score stale-claim rate and recovery |
| long-lived session | issue repeated graph-heavy tasks and measure amortized setup/resource cost |
| lazy loading | start without the tool, load only for a graph-shaped task, then stop it |
| scale/portability | repeat on a larger or different-language repository and, if relevant, cross-repo tasks |

Do not restore eager loading merely to test these cells. Use temporary per-process configuration and preserve the production baseline.

## Subagent/orchestration tools

### Natural mutation A/B

Use identical outcome prompts; do not mention or force delegation. Each run gets a fresh disposable worktree.

Recommended workloads:

1. root-cause diagnosis plus minimal fix;
2. multi-file feature implementation;
3. cross-platform configuration change;
4. regression-test creation plus fix;
5. review a flawed patch and repair it;
6. refactor with caller and compatibility preservation;
7. CI failure diagnosis followed by an executable fix.

Primary scoring:

- acceptance and hidden tests;
- final patch correctness and scope;
- no security/data-loss regression;
- no unrelated failures;
- repair cycles and time to first passing patch;
- diff size/files touched;
- inclusive parent/child tokens, cost, tools, errors, failures, and wall time.

### Explicit orchestration supplement

Report separately from the natural aggregate:

- parallel independent research lanes;
- one writer plus an independent static reviewer;
- isolated worktree integration;
- background child completion and later resume;
- council/advisor decision on an ambiguous design;
- cross-repository coordination when it is a real production need.

A no-subagent variant may perform work sequentially, but cannot claim equivalent orchestration capability. Score final outcomes and clearly label capability loss.

## Acceptance checklist

- One controlled candidate difference per comparison.
- Frozen revision, prompts, rubrics, fixtures, and hidden tests before trial 1.
- Seven paired trials per workload unless cost forces a disclosed reduction.
- Alternating A/B order, rotated workloads, fresh IDs, exact matrix assertion.
- Candidate selection frequency reported.
- Parent and every child provider/tool event included once.
- Failed launches and missing child sessions disclosed, never estimated silently.
- Live configuration and repository hashes restored.
- Decision states exactly which workflows remain unverified.
