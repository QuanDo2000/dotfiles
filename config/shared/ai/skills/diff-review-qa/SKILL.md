---
name: diff-review-qa
description: Review a PR, commit, or working-tree diff with scoped independent reviewers and evidence-based closeout. Use for explicit code review, PR review, pre-commit QA, or final QA requests.
---

# Diff Review QA

## Workflow

1. Resolve review target: PR diff, commit range, staged diff, or working tree. Capture diff once; do not make every reviewer rediscover scope.
2. Keep small diffs with one reviewer. For substantial diffs, split disjoint file groups by feature/locality and give each reviewer only assigned paths plus needed surrounding context.
3. Require findings only: severity `P0`–`P3`, confidence, exact `path:line`, failure mode, and smallest fix. No praise, style-only noise, or speculative findings.
4. Parent checks each finding against source and rejects duplicates or unsupported claims before any fix.
5. One writer applies accepted fixes. Parent runs repository's named validation commands and inspects output.
6. Independent reviewer checks final diff and validation evidence. Parent reports unresolved risks; no clean verdict without fresh evidence.

## Boundaries

- Review does not auto-fix findings.
- Do not delegate tiny diffs or duplicate same files across reviewers.
- Review changed behavior and impacted callers, not unrelated repository code.
- Repository tests, lint, typecheck, and build remain authoritative over reviewer claims.
