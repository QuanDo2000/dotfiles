---
name: agent-tool-benchmarking
description: Use when A/B benchmarking an agent tool or extension.
version: 1.1.0
---

# Agent Tool Benchmarking

Benchmark a concrete configuration decision, not model capability in the abstract. Skip expensive A/B runs when capability inventory already settles the decision: keep uniquely needed capabilities, and statically audit unreferenced dependencies.

Freeze tasks, correctness rubrics, variants, accounting, and stopping conditions before collection. Preserve production setup in A; change only the candidate in B. Label isolated tests and simulations as such. Use fresh sessions, alternate order, and record versions, effective tools, selection, and loaded instructions.

Grade correctness separately from efficiency. Report per-task raw results, wall time, provider turns, tool calls/errors, input/cache/output tokens, and reported cost; include child work and excluded attempts. Inspect token schema semantics: add cached tokens only when input excludes them. Do not equate estimated cost with subscription billing.

A single pair is exploratory, not removal proof. Zero selection measures exposure/nonuse, not utility when invoked. Limit verdicts to exercised workflows; do not generalize read-only or simulated checks to implementation or deployment.

Sandbox model tools away from credentials and live state; prove isolation before inference. Audit the first cell and pair before expansion. Invalid harness/transport attempts stay excluded from correctness but retain spend. Preserve raw events and a reusable runner; verify calculations and matrix completeness before reporting. No configuration changes or publication without authorization.

## Load the applicable procedure

These references retain the detailed contracts; load them at the stated boundary, not all at startup.

| When | Required procedure |
|---|---|
| Designing or collecting trials, including pilots | [Execution protocol](references/execution-protocol.md): baseline, containment, authentication, approved budget, trial count, finalization, cleanup |
| Interpreting/reporting results or applying a verdict | [Interpretation](references/interpretation.md): zero selection, cache accounting, resource tradeoffs, decision scope |
| Removing or substituting a capability | [Removal decisions](references/removal-decisions.md): workload coverage and capability-specific follow-ups |
| Delegation/subagent candidate | [Subagent ablations](references/subagent-ablations.md): natural selection, role coverage, inclusive child accounting |
| Memory candidate | [Memory ablations](references/memory-ablations.md): stores, canaries, compaction, coexistence |
| Web-access candidate | [Web-access ablations](references/web-access-ablations.md): search/fetch parity, runtime routes, security |
| Replicating in another client | [Cross-client replication](references/cross-client-replication.md): unchanged workloads, native adapters, pilot limits |

The selected procedures link to version-scoped examples and specialized checklists. Those examples never override current authorization, spending limits, or correctness requirements.
