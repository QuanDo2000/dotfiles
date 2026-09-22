# Codex native multi-agent natural-adoption A/B

Validated on Codex CLI `0.152.1` against Backstage `v1.54.6` at `0e67bc1fc88fba3a8cb716d3584cef05ecbcf9a8`.

## Shape

- Variant A: production-shaped configuration with native `multi_agent=true`.
- Variant B: identical except `multi_agent=false`.
- Seven trials × six mutation workloads × two variants = 84 canonical cells.
- Outcome prompts did not force delegation; parent and child accounting was enabled.
- Workloads covered architecture impact, root-cause repair, caller-preserving refactor, multi-package change, regression repair, and security/data validation.

## Result boundary

Natural delegation was selected in 0/42 enabled cells: zero spawn requests and zero child threads. Correctness was 32/42 enabled versus 33/42 disabled; paired outcomes were one enabled win, two disabled wins, and 39 ties. This supports disabling default exposure for the tested production workloads while retaining an explicit per-run path. It does not measure forced-use utility.

The enabled side used fewer mean tokens and projected cost, but no child was launched. Treat those differences as stochastic configuration-exposure observations, not evidence that delegation improved efficiency. The multi-package workload failed on both variants in every trial, so report that stratum as a workload/harness limitation rather than candidate evidence.

## Durable harness lessons

1. In Codex cumulative telemetry, `input_tokens` included cached input. Account total tokens as `input_tokens + output_tokens`; derive uncached input as `input_tokens - cached_input_tokens`. Adding cached input again silently inflates totals.
2. A grader exit of 1 can be a valid correctness failure. Execution validity comes from provider/transport exit, telemetry completeness, and explicit invalid-execution state; verify the grader and result agree instead of requiring every grader exit to be zero.
3. When the approved ceiling changes, update and verify every gate, report, and final validator. A stale literal in an independent verifier can reject an otherwise valid completed matrix.
4. After a supervising runtime restart, trust atomic artifacts rather than process history. If the next cell has no launch record, provider output, auth copy, worktree, or usage, remove only that empty placeholder and resume from the first missing canonical cell. Preserve completed cells unchanged.
5. Agent-chosen repository-wide generators, typechecks, builds, and lints can exceed a bounded worker even when focused graders fit. Quarantine provider-started OOM attempts, retain their projected spend, verify cleanup, document one symmetric bounded-command amendment, and rerun the same logical cell fresh.
6. Finalization order: complete matrix → raw reparse → execution/grader consistency → configuration hashes → cleanup checks → regenerate summary/report → machine-check report versus summary → checksum all retained artifacts, including raw telemetry, last.

## Verified outcome

The complete audit had 84 unique parent threads, zero child threads, stable distinct variant hashes, a clean pinned source checkout, one base worktree, no ephemeral auth copies, and a passing checksum manifest. Inclusive projected spend was $56.340687 under an approved $80 ceiling. Wall time was excluded because unrelated host load contaminated timing.
