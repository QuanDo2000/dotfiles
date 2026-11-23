---
name: systematic-debugging
description: Use when diagnosing bugs, test failures, or unexpected behavior.
---

# Systematic Debugging

Locate the likely failing boundary using the cheapest available evidence. Prefer a fix at the shared cause, then verify the symptom and affected contracts using `tdd` and the governing verification policy. Label an unproven cause provisional; do not attribute a combined experiment to one variable without evidence. For deep tracing, validation placement, or flaky waits, load `troubleshooting.md`.

Keep investigation-only requests read-only. Validate paths and object identities before acting; check current state rather than treating historical reports as proof. Continue useful bounded work within existing authority and ask only when the next step needs broader authority. Report the evidence, smallest fix, verification, and residual risk.
