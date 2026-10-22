# Removal ablations: prove the decision boundary

Paths below are relative to this reference directory.

A removal result is only as broad as the workflows exercised. State that boundary explicitly instead of promoting a read-only result into a universal claim.

For **code-intelligence/index tools**, a strong read-only suite covers architecture reconstruction, impact tracing, root-cause localization, and implementation planning, and must prove the candidate was selected. Before claiming equivalence for implementation work, add separate cells for edits plus incremental change detection, cold indexing, stale/partial indexes, refactors with caller preservation, long-lived-session amortization, and lazy/on-demand loading. A warm copied graph with fresh no-session parents supports an eager-loading decision, not universal removal.

For a comprehensive decision, use a genuinely large pinned monorepo and real disposable-worktree edits. Freeze at least six normal warm workflows spanning architecture/impact, root-cause fix, caller-preserving refactor, multi-package change, regression-test repair, and security/data validation. These routine workflows drive the primary verdict (about 90% decision weight). Startup, empty-cache indexing, graph-build modes, specialized conformance, and cleanup remain separately reported lifecycle metrics (about 10% unless a safety or reliability failure is catastrophic); do not let one-time setup dominate routine-use quality.

Prove the tested version boundary before trial 1: compare the installed binary version and actual registered tool schemas with the latest published immutable release and its tagged documentation. Pin release/tag commits and record discrepancies with current unreleased source; never silently benchmark a tool present only on `main` as part of the released product.

For **subagent/orchestration tools**, separate two suites:

1. **Natural mutation A/B:** identical outcome prompts that do not force delegation. Use isolated disposable worktrees; score executable patches with acceptance tests, hidden regressions, scope control, security/data-loss checks, repair cycles, wall time, and inclusive parent/child usage.
2. **Explicit orchestration supplement:** parallel research lanes, one writer plus independent reviewer, isolated worktree integration, background/resume, and council/advisor flows. Report this separately because a no-subagent variant can work sequentially but cannot preserve the same orchestration capability.

Do not combine removal of two candidates in one variant. If a mutation benchmark exposes a graph-shaped gap after removing an eager code-index tool, benchmark lazy/on-demand loading separately.

For agent-side LSP extensions, use `lsp-extension-ablation.md` to cover natural mutation work, provider-free schema/failure conformance, configured-language runtime proof, per-call server lifecycle costs, and native-checker comparison.

For package and capability substitutions, use `dependency-substitution-parity.md` to compare release freshness, cross-platform ownership, rule-level parity, and uniquely reclaimable Nix closure rather than headline package size.

See `removal-ablation-coverage.md` for reusable workload matrices and acceptance criteria. For a comprehensive code-intelligence ablation covering large monorepos, edits, lifecycle behavior, lazy loading, and every advertised capability, use `code-intelligence-comprehensive-ab.md`.
