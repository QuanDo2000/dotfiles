# Resumable serial benchmark matrices

Use this when a long provider-backed matrix fails after valid cells have completed.

## Recovery contract

1. Treat the canonical matrix as an ordered journal. Persist each cell only after raw events, metadata, correctness evidence, and completion timestamps are durable.
2. Reparse retained cells from raw events before resuming. Assert unique `(trial, workload, variant)` keys, unique provider thread/session IDs, frozen snapshot identity, and expected canonical prefix order.
3. Classify the failed position before retrying:
   - **Pre-provider preparation failure:** quarantine setup logs; record that no provider work occurred.
   - **Provider call started:** preserve it as excluded provider work and count its usage against the approved spend ceiling.
   - **Ambiguous:** conservatively treat it as provider work until raw evidence proves otherwise.
4. Fix only the harness preparation defect. Do not alter prompts, rubrics, fixtures, variant structure, model settings, or canonical ordering.
5. Resume at the first missing canonical position. Never rerun valid cells merely to simplify the runner.
6. After completion, regenerate blind scoring, independent reparsing, paired summaries, cost accounting, cleanup evidence, and checksums from the final canonical set plus the excluded-attempt ledger.

## External-load overlap audit

Record external activity as exact UTC intervals. Compare it mechanically with authoritative per-cell `launch_started` and `launch_finished` timestamps using interval intersection—not process snapshots, log ordering, or approximate next-start times. If a cell overlaps:

- quarantine and rerun only that cell under clean conditions;
- count the original provider work as excluded spend;
- regenerate every downstream artifact;
- retain an incident JSON containing both intervals and the decision.

A gap between neighboring cells needs no rerun, but the conclusion must come from final cell metadata rather than an early progress estimate.

## Final invariants

- Exact matrix cardinality and one row per canonical cell.
- All retained rows independently reparsed from raw events.
- Excluded attempts are not silently discarded and remain in spend/provenance accounting.
- Frozen repository/config identity is unchanged.
- Owned worktrees, caches, processes, and runtime directories are cleaned.
- Checksums are generated only after all corrections and report regeneration.
