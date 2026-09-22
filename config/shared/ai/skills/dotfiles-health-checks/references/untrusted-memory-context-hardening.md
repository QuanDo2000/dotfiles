# Hardening Writable Agent Memory Context

Use this when an agent extension reads writable Markdown, daily logs, scratchpads, or search hits and appends them to a privileged system/developer prompt.

## Threat model

The durable store may contain text copied from web pages, documents, tool output, another agent, or an earlier compromised turn. Safe file permissions do not make that text trusted. A write path that accepts arbitrary text is not itself the critical defect; automatic elevation of that text into a privileged prompt is.

## Smallest complete fix

If ambient injection is not mandatory, remove the shared hook that concatenates stored content into the system prompt. Keep explicit memory tools:

- write/forget/restore preserve persistence;
- read/search return content as ordinary tool results;
- status remains available;
- no blocklist or new dependency is needed.

A warning wrapper, XML delimiter, JSON encoding, or phrase scanner is defense-in-depth, not a complete trust-boundary fix. Do not represent it as one.

## Declarative package patch

For an immutable npm closure managed by Nix and Windows staging:

1. Patch the pinned package after dependency installation but before publishing the release directory.
2. Match unique start/end source markers around the privileged injection hook; reject missing, duplicate, or reversed markers before writing.
3. After transformation, reject any remaining privileged hook/signature.
4. Run the same transformer in every platform installer.
5. Extend installed-release validation so a pre-existing unpatched directory is rejected rather than accepted merely because package versions match.
6. Keep lifecycle scripts disabled unless independently required and reviewed.

A source transformer is preferable to maintaining a fork when the change is tiny, pinned to one reviewed release, and guarded against upstream drift. Upgrade only after the transformer either applies cleanly to the reviewed source or is deliberately replaced.

## Regression and deployment proof

Test-first behavior:

1. Write malicious text through the real memory-write tool into an isolated memory directory.
2. Execute registered pre-agent hooks without a provider call.
3. Require the payload to remain stored, remain absent from returned system-prompt mutations, and require explicit memory tools to remain registered.
4. Add one drift test proving an unknown source is unchanged and the transformer exits nonzero.

Deployment gates:

- immutable package build and install check pass;
- independently patched pinned entry hash equals the deployed entry hash;
- deployed source contains no privileged injection hook/signature;
- fresh provider-free RPC startup succeeds with empty stderr;
- memory-file hash is unchanged across startup;
- focused Unix and cross-platform installer tests pass;
- full repository check, doctor, dependency audit, and failed-unit checks pass;
- prior generation and state remain available for rollback.

## Reverting to upstream behavior

If the user explicitly chooses upstream automatic recall after the trust tradeoff is stated, remove the transformer, hardening-only validation, and hardening-only tests rather than replacing them with another custom injection layer. Create a new immutable release identity even when dependencies are unchanged, then verify the deployed source contains the upstream hook, fresh provider-free startup succeeds, and memory content remains stable. Retain generic package-integrity and cross-platform installer checks.

## Reporting boundary

Say: “Stored memory no longer enters the privileged system prompt.” Do not say all prompt injection is solved. Explicit `memory_read` or `memory_search` results remain untrusted tool data and must be handled under normal tool-output trust rules. When upstream behavior is deliberately restored, state plainly that automatic recall and the known trust-boundary risk are both restored.
