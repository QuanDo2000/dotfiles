---
name: test-driven-development
description: "Use for behavior-changing code or bug fixes."
version: 1.3.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [testing, tdd, development, quality, red-green-refactor]
    related_skills: [systematic-debugging, subagent-driven-development]
---

# Reusable Execution and Focused Verification

Build the working capability, not a growing collection of one-off tests. Prefer a small number of real-flow checks through actual entry points. Test count and coverage percentage are not completion criteria.

## Choose the minimum useful checks

- Before implementation, name the user-visible outcome and credible failures. Choose the smallest existing check that can catch them.
- Add focused tests when useful; avoid duplicate E2E assertions and unnecessary fixtures.
- Batch related edits into a coherent change, then run affected checks. Do not rerun the full suite after every edit, handoff, or prose change. During development, run a targeted check when its result will change the next implementation decision.
- Reuse passing results for an unchanged tested component when its inputs, dependencies, environment, and relevant contract remain unchanged, even if unrelated files or the overall revision changed. State the checked scope and why it remains applicable; never describe an old full-suite run as a pass on a new head. Required exact-head gates still run on the final head.
- Assert observable output, durable state, exit status, or a boundary contract with independently derived expectations. Do not test private structure or grep source text merely to prove an edit happened.

## Bug fixes: risk-based symptom reproduction

For security or data-loss risk, use the baseline and patched reproducer below. For other fixes, focused final-state verification may suffice; disclose when the baseline was not run.

1. Reuse or create one reproducer for the reported symptom. Reuse a recorded diagnostic baseline only if the same reproducer ran on the relevant baseline revision under equivalent conditions and failed for the intended reason, not a setup error. Otherwise, establish that failure with a safe baseline run.
2. Fix the shared root cause, batch related corrections, and run the same reproducer against the patched revision under equivalent conditions: baseline fails, patched passes.
3. Rerun only checks affected by subsequent behavior changes, plus applicable final repository gates. Do not repeat the baseline or recreate the harness for every refinement unless the reproducer or relevant assumptions changed.

Preserve unrelated work and baseline failure evidence. If a safe baseline run is unavailable, disclose that limitation; do not manufacture RED or claim test-first execution retroactively.

## Safe execution and completion

Use disposable state or an approved test environment. Production data, credentials, deployments, paid services, one-shot allowances, and explicit approval boundaries remain protected. Exercise real components; disclose unavoidable substitutions and unavailable coverage. Mock-backed checks are not E2E evidence.

Use existing runner output rather than a separate evidence framework. Redact secrets and private data. A screenshot alone does not prove hidden state or safety properties.

At completion, follow the governing verification policy for focused checks, applicable repository gates, and scoped exceptions on the final revision. Inspect actual exit status and relevant output; report passed, failed, reused, skipped, and unverified checks. Child reports alone are not verification.
