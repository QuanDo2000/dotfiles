---
name: systematic-debugging
description: Use when a bug, test failure, or unexpected behavior needs root-cause diagnosis before a fix
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

For multi-component flows, record input/output/state at each boundary once. Do not add broad logging everywhere.

## 2. Test one hypothesis

State: **“X is the cause because evidence Y; check Z will distinguish it.”**

Run the cheapest discriminating check. Change one variable. If disproved, discard it before testing another; never stack speculative fixes.

After two failed hypotheses, stop and redraw the data/control flow before attempting another edit. Repeated local patches usually mean the failure boundary is wrong.

## 3. Fix the shared cause

Trace every caller of the function or configuration being changed. Prefer one correction at the shared boundary over guards in sibling callers.

Use the `test-driven-development` skill for writing proper failing tests. Keep the regression focused on the observed behavior. Do not bundle cleanup.

## 4. Verify efficiently

Run the focused reproducer first, then the smallest authoritative regression scope. Run broad suites once at finalization only when the changed surface requires them; do not rerun unchanged expensive checks on the same revision.

Use the `verification-before-completion` skill before claiming success.

## Stop conditions

Stop and report evidence when:

- the failure cannot be reproduced or required live state is unavailable;
- mutation would precede a decisive read-only gate;
- two hypotheses failed and architecture/control flow is still unclear;
- the safe fix requires broader ownership or user approval.

Report: failing boundary, root cause/evidence, smallest fix, verification, residual risk.
