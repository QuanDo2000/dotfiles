# Cross-client pilot interpretation

Use this checklist when porting a validated benchmark to another agent client with one paired trial per workload.

## Evidence to retain

- Exact reduced matrix and unique session/thread IDs.
- Frozen source revision, unchanged prompts, mutations, rubrics, visible tests, and hidden tests.
- Structural proof that variants differ only by candidate exposure.
- Independent raw-event reparse for usage, calls/results, answers, and serial ordering.
- Before/after hashes for live config and candidate state; disclose volatile client caches separately.
- Excluded-attempt provenance instead of silently replacing failed adapter runs.

## Interpretation

A candidate selected in zero eligible runs was exposed but unused. Such a pilot measures registration/startup overhead and the production agent's natural non-selection; it does not establish whether the candidate helps when used. Do not force use in the primary production-shaped matrix. If discoverability matters, diagnose it separately or add a clearly labeled forced-use supplement.

Report correctness at consistent levels. A blind-scored architecture workload can count as one workload pass while hidden mechanical pass counts cover only mutation workloads. Publish both denominators rather than comparing them directly.

One paired trial is a smoke-quality directional result. Even tied correctness and modest resource deltas do not justify production configuration changes; confirmation requires the normal interleaved seven-trial matrix.
