# Codex cross-client benchmark notes

Use this when adapting an existing production-shaped benchmark to Codex CLI. Re-probe every CLI version; these are validated adapter patterns and version-scoped observations, not permanent capability claims.

## Minimal adapter

- Run each cell as a fresh `codex exec --ephemeral --json` process with a unique thread ID.
- Build isolated per-variant homes from allowlisted non-secret production configuration. Preserve model, reasoning, instructions, skills, plugins, auth mechanism, sandbox, approvals, and unrelated MCP servers without copying the whole live home. Keep sessions and credentials excluded; any credential transport requires the owning skill's separate approval and cleanup procedure.
- Remove only the candidate MCP table in the ablated variant. Compare the resulting configurations structurally before canonical collection.
- Use disposable worktrees and isolated candidate caches/daemons. Never point canonical runs at live candidate databases.
- Quarantine schema/config smoke runs. Reuse their proof for a later full matrix when the adapter and versions are unchanged instead of buying duplicate smoke runs.

## Usage accounting

Codex 0.150.1 JSONL exposed input, cached-input, cache-write-input, output, and reasoning-output fields but no monetary cost. Cached input was represented as a subset of input, so the validated report used `input + output` rather than adding cached input again. It exposed one `turn.started` per exec, not authoritative underlying provider request counts.

Always inspect the current event schema. If cost or provider turns are absent, mark them unavailable. A projected spend gate may use a prior empirical rate, but label it as a projection and include smoke, retries, and excluded attempts. Freeze the current task's explicit ceiling into the preflight JSON and report; do not let a stale pilot/default gate override it. A gate failure before provider calls is safe to correct in place once the authoritative ceiling and inclusive projection are verified.

## Correctness and tool selection

- Keep blind architecture scoring separate from hidden mechanical-test counts; report both before aggregating workload correctness.
- Process exit 0 is not patch correctness. Require the expected patch plus visible and hidden checks.
- Production skills may cause an agent to stop for design approval. Preserve that behavior symmetrically; score an absent patch as incorrect rather than silently completing it outside the agent.
- Zero candidate calls means natural non-selection/default-exposure evidence, not candidate utility. This is still actionable for a default-list decision: across a substantial representative matrix, zero selection plus tied correctness supports removing default exposure while retaining explicit/on-demand access. Do not claim the candidate is intrinsically useless, and do not force use in the production matrix.
- Never attribute no-call A/B latency or token differences to candidate utility. If utility when invoked matters, run a separately labeled forced-use supplement.

## Quarantine and final report regeneration

- For a bounded competing-I/O event, intersect the exact event interval with recorded cell launch intervals. Do not infer a cell start from the preceding completion plus an assumed setup gap.
- Quarantine and rerun only actual overlaps. Count the excluded attempt in projected spend and retain it outside the canonical 84-cell set.
- A replacement can change aggregate means materially. Rebuild raw reparse, blind scores, summary, report, cost gate, cleanup evidence, and checksums in dependency order; checksums are last.
- Add a machine-readable report-versus-summary consistency artifact. A report that mentions the replacement can still contain stale pre-replacement metrics.

## Live-state audit

Isolated benchmark processes can leave critical live configuration untouched while pre-existing Codex app servers update volatile files such as model caches or log databases. Compare only allowlisted non-secret configuration and candidate logical databases, separately from broad volatile state. Keep auth opaque: never read, hash, or diff credential bytes. Disclose unverified credential-content preservation and volatile changes; never claim byte-for-byte invariance when unrelated app servers changed live files.

## Post-benchmark default removal

When zero natural selection leads the user to remove the candidate from Codex's default list:

- Remove only the live registration and tracked shared/platform Codex config blocks. Keep the binary/package available for explicit specialized use unless removal was requested.
- Search tests and fixtures for positive assertions that the old default registration exists. Update them to explicit negative regression assertions in the same change; otherwise cross-platform CI can reject an otherwise correct deletion.
- Verify the live client lists no default server, the retained binary still resolves, all tracked TOML parses, platform CI reaches terminal success, and local/remote revisions match.
- Keep Codex's backup-agent role minimal: do not replace the removed integration with a Pi-like tool suite without a demonstrated Codex-specific need.

## Support-policy boundary

Inventory only user-supported clients. A stale configuration is not a benchmark target. If the user declares a client unsupported, exclude it from matrices and recommendations; do not suggest installing it later. Remove stale active integration artifacts only when requested, while leaving third-party upstream documentation and historical logs alone unless the user explicitly requests a history scrub.
