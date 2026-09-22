# Pi Concurrency and Policy Boundaries

Use for an installed subagent extension, not as a claim about Pi core. Inspect the installed version, active API, configuration resolver, and executor before naming controls or asserting enforcement.

## Verify the lifetime

Keep per-call task count, simultaneous children per run, cumulative session spawns, nesting depth, and session/process-wide concurrency separate. N total agents means one parent plus N−1 children. A spawn budget is not a live-concurrency limit; a per-run semaphore does not bound overlapping runs. Check every active launch path, including workflow helpers, instead of trusting legacy settings.

Prefer native controls plus non-overlapping workflows where sufficient. Add an outer scheduler only for an observed strict aggregate-limit requirement. Claim enforcement only after a safe bounded fan-out exercises the required lifetime; JSON inspection proves configuration, not runtime enforcement.

For model scope, inspect explicit, inherited, fallback, and project-overridden selections separately. Determine warning versus rejection behavior from current code and relevant smoke checks. A routing allowlist is not a security sandbox; see `pi-model-routing.md` for effective selection and auth boundaries.

## Preserve deployment ownership

Locate the current runtime config rather than assuming a historical path. Distinguish a writable preference seed from authoritative policy: a three-way merger may preserve live increases and write them back to tracked sources. A hard ceiling needs an authoritative deployment path that fails closed on synchronization errors.

For authorized deployment changes, preserve cross-platform paths, atomic same-directory replacement, explicit owner-write permissions, and target/baseline consistency. Copying read-only store files can make the next activation fail. In disposable fixtures, cover fresh creation, missing baseline, stale live values, and a second activation; check contents, permissions, and leftover temporary files. Do not weaken ownership or scope guards to make activation pass.

Re-read live configuration and verify in a fresh session when startup state is cached. State precisely whether evidence covers per-call, per-run, session-wide, or process-wide limits; disclose any unsupported launch path.
