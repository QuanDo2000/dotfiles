---
name: test-driven-development
description: "Use for behavior-changing code or bug fixes."
version: 1.2.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [testing, tdd, development, quality, red-green-refactor]
    related_skills: [systematic-debugging, subagent-driven-development]
---

# Real-Flow and A/B Regression Verification

Verify real workflows, not test volume. Prefer a small number of repeatable end-to-end checks through actual entry points. Test count and coverage percentage are not completion criteria.

## Choose the evidence

- Before implementation, name the user-visible outcome and credible failures, including relevant security, data-loss, and rollback risks.
- Inspect the real entry point, dependencies, and existing checks. Reuse a check that catches the failure instead of adding redundant coverage.
- Do not add unit tests by default or duplicate E2E assertions. Add a focused test only when an important correctness or safety failure cannot be exercised safely and reliably end to end.
- Assert observable output, durable state, exit status, or a boundary contract, using independently derived expectations. Do not test private structure or grep source text merely to prove an edit happened.

## Bug fixes: baseline versus patched

1. Start with a reproducer for the reported symptom, not an expectation inferred from the proposed fix. Run it against the baseline and confirm failure for the intended reason, not a setup error.
2. Fix the shared root cause under approval, preserving unrelated work.
3. Run the same reproducer against the patched revision under equivalent conditions: baseline fails, patched passes. This is A/B regression verification, not statistical experimentation.
4. Simplify only after the check passes, then rerun affected checks. Add another check only for an important uncovered failure, not every function or line.

If the fix already exists, establish the baseline in isolation. Do not discard existing work, weaken expectations to manufacture failure, or claim test-first execution retroactively. Disclose when a safe baseline run is unavailable.

## Safe, repeatable real-flow checks

Use disposable state or an approved test environment. Do not touch production data, credentials, deployments, or paid services without authorization. Exercise real components; substitute only unavoidable external, nondeterministic, costly, or unsafe boundaries. Disclose substitutions and unavailable coverage; mock-backed checks are not E2E evidence.

For complex workflows, retain the revision, exact command, prerequisites/fixtures, expected and actual outcomes, and an inspectable artifact such as existing runner output or verified resulting state. Redact secrets and private data. Do not build an artifact framework; a screenshot alone does not prove hidden state or safety properties.

## Completion

- Run impacted checks and applicable repository gates on the final revision. Inspect exit status, failures, and relevant output; child reports and old logs are not substitutes.
- Report passed, failed, skipped, and unverified checks. Reuse results only while revision and inputs remain unchanged.
- Configuration may use native parsing, evaluation, or existing validation. Prose needs review, not substring tests. Exercise instruction changes with representative consuming-agent scenarios when a harness is available; otherwise report static review only.
