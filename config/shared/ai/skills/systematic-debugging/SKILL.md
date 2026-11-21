---
name: systematic-debugging
description: Use when diagnosing bugs, test failures, or unexpected behavior.
---

# Systematic Debugging

**Rule: no fix before the failing boundary and root cause are evidenced.**

## 1. Establish facts

1. Read the complete error and exact command/output.
2. Reproduce the smallest failure. If intermittent, capture conditions instead of guessing.
3. Check live state and recent changes. Historical artifacts and child reports are leads, not current proof.
4. Validate paths and object identities before reading or patching generated files; search current artifacts rather than guessing names.
5. Trace the value/state backward through callers and component boundaries until the first wrong assumption or transition is found.
6. Find one nearby working path and compare only relevant differences.

For multi-component flows, record input/output/state at the suspected boundary; expand only when evidence requires it. Do not add broad logging everywhere. For deep tracing, validation placement, or flaky waits, load `troubleshooting.md`.

## 2. Test one hypothesis

State: **“X is the cause because evidence Y; check Z will distinguish it.”**

Run the cheapest discriminating check. Prefer changing one variable; do not attribute the outcome of a combined experiment to one variable without evidence. Discard disproved hypotheses. After repeated failures, reassess the data/control flow when doing so would clarify the next check; use fresh evidence rather than a fixed attempt count.

## 3. Fix the shared cause

Trace every caller of the function or configuration being changed. Prefer one correction at the shared boundary over guards in sibling callers.

Use the `tdd` skill for writing proper failing tests. Keep the regression focused on the observed behavior. Do not bundle cleanup.

## 4. Verify efficiently

Run the focused reproducer first, then the smallest authoritative regression scope. Run broad suites once at finalization only when the changed surface requires them; do not rerun unchanged expensive checks on the same revision.

Follow the global verification policy before claiming success.

## Evidence gaps

Prefer a decisive read-only check before mutation. If reproduction or live evidence is unavailable, name what is unknown and continue any useful, bounded work already authorized. Defer speculative edits by default; follow the governing scoped-exception rule for an explicitly authorized diagnostic change or reversible mitigation. Ask only when the next step genuinely needs broader authority.

Report: failing boundary, root cause/evidence, smallest fix, verification, residual risk.
