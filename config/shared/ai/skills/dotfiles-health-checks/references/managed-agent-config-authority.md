# Managed agent config authority

Use this checklist when dotfiles deploy writable AI-agent settings or concurrency policy.

## Choose ownership first

- **Mutable seed:** three-way merge tracked defaults, prior baseline, and live state; appropriate for user-tuned preferences.
- **Authoritative policy:** tracked file always replaces live state; appropriate for provider restrictions, role routing, and child-count limits that must not drift upward.
- Do not call a mutable seed a hard policy: a live edit can be merged back into the repository on activation.

## Atomic authoritative deployment

On Unix, create temporary files beside both destination and baseline, copy the tracked source, set owner-writable mode (normally `0600`), then rename into place. A direct copy from a read-only Nix-store source can create a read-only fresh baseline and make the next activation fail. Same-directory rename also prevents readers from seeing partial JSON.

On Windows, copy to a unique same-directory temporary path and replace with `Move-Item -Force`; update both destination and baseline. Keep Unix and Windows destination paths and semantics in parity.

Verify:

1. delete only the disposable baseline;
2. activate once and assert exact contents plus writable mode;
3. tamper the live policy value;
4. activate again and assert the tracked value is restored;
5. activate a third time to prove idempotence;
6. assert no temporary files remain.

## Git-backed flake boundary

A repository-local `path:` evaluation can see files that a Git-backed flake or clean checkout omits. If Nix references a new seed file, ensure it is tracked before treating builds as reproducibility evidence.

## Storage is not runtime enforcement

Before claiming a configured concurrency ceiling:

1. inspect the pinned runtime implementation and every active execution API;
2. distinguish per-call, per-run, workflow, session, and process-wide semaphores;
3. exercise the current public API with more than the configured limit when a hard cap is required;
4. name tests after what they prove (`configures native per-run limits`, not `caps concurrency`) when enforcement is incomplete;
5. document the smallest operational fallback, such as no overlapping workflows and no more than N children per workflow, rather than adding an unneeded custom scheduler.

Provider/model scopes deserve the same distinction: warnings and inherited fallback behavior are guardrails unless the runtime demonstrably rejects every out-of-scope route.
