---
name: test-driven-development
description: Use for behavior-changing code or bug fixes; prove one focused regression RED, then GREEN
---

# Test-Driven Development

For each changed behavior:

1. **RED:** write the smallest test that exercises the real public boundary and fails for the intended reason.
2. **GREEN:** add the least production code that passes it.
3. **REFACTOR:** remove duplication only while tests remain green.

Do not write implementation first, test mocks instead of behavior, or broaden scope beyond the failing example.

## RED

- Name one behavior; avoid “and”.
- Use real code. Mock only unavoidable external boundaries.
- Run only the focused test.
- Confirm it fails—not errors—because the behavior is missing or wrong.
- If it passes immediately, improve the test; it proves no regression.

A bug fix requires a reproducer for the original symptom. A configuration-only change may use the repository's smallest existing validation/assertion instead of inventing a unit framework.

## GREEN

Write the smallest root-cause fix. Do not add options, abstractions, refactors, or “future” behavior. Run the focused test until green.

## REFACTOR

Only after green: simplify names/duplication, then rerun the focused test.

## Final verification

Run impacted tests once, then the repository's broader required gate if the changed surface warrants it. Do not repeatedly run a full suite while iterating on one test or rerun unchanged validation on the same revision.

Before completion, verify:

- the test fails without the fix and passes with it;
- the assertion checks user-visible behavior or durable state;
- relevant existing tests pass;
- no unrelated production change was bundled.

Exploration is allowed when the interface is unknown, but discard exploratory production changes before the RED/GREEN cycle.
