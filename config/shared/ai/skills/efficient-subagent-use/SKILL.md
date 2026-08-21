---
name: "efficient-subagent-use"
description: "Delegate independent substantial lanes without duplicate work, polling, or unnecessary context"
version: 6
created: "2026-08-07"
updated: "2026-08-21"
---

# Efficient Subagent Use

This skill owns delegation decisions, lane sizing, and cost control; harness-specific skills own execution APIs and mechanics.

## Gate

Delegate only when either:

- two or more independent substantial lanes can run in parallel; or
- one bounded lane can run while the parent continues useful work.

Otherwise work directly. Startup, schemas, duplicated discovery, and synthesis are real costs.

## Procedure

1. Reuse known configured roles. List agents only when capability or model availability is unknown.
2. Check active/completed runs for the same lane and target revision. Reuse the artifact or retained child; relaunch only when target/evidence changed.
3. Use 1–3 narrow children, normally one fan-out wave. A second wave needs a concrete changed target or unresolved evidence gap.
4. Parallelize read-only discovery/review. Keep one writer per worktree.
5. Use one reviewer by default; add a second only for a distinct high-risk angle.
6. Launch asynchronously only when the parent can continue useful work or yield for completion. Do not launch async and immediately wait.
7. Pass only governing matched skills through the child `skill` field; do not enable global skill inheritance. Builtin Pi roles do not inherit the discovered skill catalog.
8. Give each child only: goal, necessary paths/evidence, constraints, output shape, success criteria, and stop rule. Do not paste full history or broad repository context.
9. For read-only scouts and reviewers, set `agentContract: { version: 1 }`, omit `acceptance`, and request only findings, exact paths, confidence or coverage, and residual risks. Do not request validation commands from static reviewers.
10. Parent verifies primary evidence once, resolves disagreement, and stops spawning when the decision is supported.

## Cost stops

- Never delegate tiny lookups, serial steps, duplicate parent work, or ceremonial review.
- Never make every reviewer rediscover the same diff; capture scope once.
- Never run parallel writers in one worktree.
- Never keep a child searching after its stop criterion.
- For substantial fleets, inspect `/subagent-cost`; reduce fanout/context before lowering model quality.

## Verification

Distinct lanes; no duplicate writer; no polling loop; parent performed final verification; synthesis contains conclusions, not copied child prose.
