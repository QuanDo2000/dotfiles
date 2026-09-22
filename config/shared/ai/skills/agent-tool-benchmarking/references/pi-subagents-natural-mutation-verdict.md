# Pi subagents natural-mutation verdict (98-cell, 2026-08-31)

Verified case: Pi 0.84.4, locked `pi-subagents` 0.60.0, 7 workloads × 2 variants × 7 trials = 98 serial provider cells on the user's dotfiles repo (disposable per-cell worktrees, hidden graders, inclusive parent+child accounting, checksums + independent reparse all PASS; $91.80 inclusive vs $150 ceiling).

## Result

| Metric | A (subagents on) | B (subagents off) |
|---|---|---|
| Hidden checks passed | 15/49 | 15/49 |
| Wall mean | 234.3 s | 154.1 s |
| Total tokens mean | 1.117 M | 708 k |
| Total inclusive cost | $52.89 | $38.90 |
| Tool calls mean | 33.1 | 29.9 |

Paired per-cell quality: net 0 (3 A wins / 3 B wins / 43 ties). Overhead: A used **+52% wall, +58% tokens, and +36% cost** versus B.

Adoption: subagents were selected in only 11/49 A cells. Parent JSONL contained **23 spawn requests** — `code-analysis.scout` 11, `reviewer` 10, plain `scout` 2 — plus **27 lifecycle calls** (`list` 11, `status` 6, `resume` 9, `interrupt` 1). Worker/researcher/oracle were never selected on mutation workloads. All active child sessions used `gpt-5.6-terra`; Luna/Sol routes were not exercised. The parent did the edits itself; only read-only scout/reviewer delegation was naturally chosen.

## Coverage limitation

The manifest proved that all configured roles existed and that routing/settings were declared, but that is not runtime coverage. This matrix did **not** satisfy a requirement to execute every enabled role, model route, and role tool restriction. Its verdict is valid for natural adoption and inclusive A/B overhead, not all-role functionality. Complete that requirement with a separately labeled forced-role supplement for researcher, worker, and oracle (plus route/tool assertions); do not rerun or contaminate the natural 98-cell matrix.

## Interpretation pattern (reusable)

1. Aggregate pass equality is not enough — compute paired A/B win/tie deltas per trial×workload. Ties dominating (43/49) is the strong signal.
2. Partial role adoption is second-order dead weight: even a "sometimes used" package may only ever use its read-only roles; the mutation-capable roles carry schema/instruction overhead for nothing.
3. Same-shaped result as the Codex CBM ablation (zero natural selection): supports removing from defaults, keeping the locked package for explicit/specialized use. Do NOT claim "subagents are useless" — only "not earning default exposure on this user's production mutation workloads." Explicit orchestration use cases (parallel research lanes, one-writer-plus-reviewer) were NOT covered by this natural matrix.
4. Workload mix matters: cells with hidden checks concentrated in 2 of 7 workloads (ci_neovim_cache, retire_migrations 7/6 and 6/7); 4 workloads passed 0 in both variants (grader targets unreachable in one turn) — report per-workload, not just aggregates.
5. Serial proof: assert per-cell `[started, started+wall]` intervals are non-overlapping and sequence numbers are exactly 1..N. Cell-end vs next-cell-start overlaps of <0.3 s are harness bookkeeping (result write + next setup), not provider concurrency.
