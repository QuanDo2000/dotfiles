---
name: test-driven-development
description: "Use for behavior-changing code or bug fixes."
version: 1.1.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [testing, tdd, development, quality, red-green-refactor]
    related_skills: [systematic-debugging, subagent-driven-development]
---

# Test-First, Real-Flow Verification

Prove observable behavior, not implementation structure. Prefer a few tests through real workflows over many internal assertions; coverage percentage and test count are not completion criteria.

## Before implementation

1. Name the user-visible outcome and credible failures, including relevant security, data-loss, and rollback risks.
2. Inspect the real entry point, dependencies, and existing checks. Choose the smallest boundary that catches the failure.
3. Prefer integration/E2E checks for complex features. Use focused unit tests for logic and failure paths that are hard, unsafe, or expensive to exercise end to end; do not duplicate assertions across layers.
4. Write the smallest failing example before changing production code. Bug fixes start with the reported symptom, not a test inferred from the proposed implementation.

## RED → GREEN → simplify

Run the focused check and confirm failure for the intended behavior, not setup errors. If it already passes, test against the revision without the fix in isolation, preserving existing work. Do not weaken expectations to manufacture RED; disclose when RED cannot be established safely.

Apply only the smallest shared root-cause fix, run the check again, then simplify while keeping checks green. Repeat for the next important behavior, not every function or line. Do not batch speculative tests, introduce future options, or bundle unrelated cleanup.

Exploration is allowed when an interface is unknown. Remove only your own throwaway exploratory changes before RED/GREEN. For existing implementation, add the missing regression and establish RED against the prior revision when safe; never discard user work or pretend the test came first.

## What earns a test

- Name the plausible defect each assertion catches. Check output, durable state, exit status, or boundary contracts using independently derived expectations.
- Do not grep source text, split constants into assertions, or freeze private structure. Exact text is appropriate when it is the required public contract.
- Use real components; substitute only unavoidable external, nondeterministic, costly, or unsafe boundaries. Inspect the actual interface and preserve the side effects and response shape consumed by the flow.
- Assert calls/arguments/order only when they are the boundary contract. A mock returning its configured answer proves nothing. If mock setup outgrows the behavior, prefer real integration.
- Keep test-only scaffolding in tests; do not add production APIs solely for tests.

## Evidence and completion

Finish complex features with a safe real-flow check and inspectable artifact: existing runner output, generated file, trace, or verified resulting state. Record revision, exact command, prerequisites/fixtures, expected outcome, and actual result. Do not build an artifact framework; screenshots alone do not prove hidden state or safety.

Use disposable state and authorized environments; redact private data/secrets. Disclose substitutions or unavailable real flows rather than claiming E2E coverage. Confirm RED/GREEN or its limitation, run impacted checks and required gates on the final revision, and inspect exit status/failures/output. Report passed, failed, skipped, and unverified checks with evidence. Reuse results only while revision and inputs are unchanged.

Configuration may use native parsing/evaluation or existing validators. Human prose needs review, not substring tests. Exercise agent instructions through representative consuming-agent scenarios when available; otherwise report static review, not behavioral validation.
