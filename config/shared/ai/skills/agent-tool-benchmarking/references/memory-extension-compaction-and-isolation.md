# Memory-extension isolation and compaction validation

Use this checklist when comparing third-party memory extensions whose storage roots, lifecycle hooks, and compaction ownership differ.

## Prove storage isolation before provider-backed collection

1. Read the candidate's path resolver, not only its README. Inventory every environment variable, settings key, home-directory fallback, project-store path, database path, daily-log path, recovery directory, and index/cache path.
2. Set the agent/client root **and** every extension-specific override. A common failure is assuming the client root redirects an extension that independently resolves `$HOME/.client/...`.
3. Start with an empty disposable cell root and a synthetic marker that cannot be confused with user data.
4. Run one write canary. Enumerate the isolated root and all live fallback targets immediately afterward. Require every new file to be under the cell root before launching the matrix.
5. Repeat with two cell roots and verify that the second cannot read the first. Reusing one store across nominally isolated seeds invalidates independence even when every answer is correct.
6. Measure candidate store bytes separately from session transcripts, auth links, settings, and model caches.

If a canary writes live state:

- stop the matrix;
- preserve the affected outputs as isolation-invalid and count their provider usage;
- inspect the exact target before deleting anything;
- remove it only when provenance proves the benchmark newly created it and every entry is synthetic;
- verify absence, correct the specific resolver override, empty all affected cell roots, and rerun every contaminated cell;
- document the incident. Never infer that final clean state retroactively validates contaminated cells.

## Prove compaction actually compressed required history

A successful compaction event does not prove useful compaction. Correct recall can come entirely from a retained raw tail.

Freeze and record:

- declared model context window;
- compaction output reserve;
- retained-recent-token tail;
- candidate auto/manual trigger thresholds;
- source token count and placement of scored facts.

Acceptance checks per cell:

1. `tokensBefore` and `estimatedTokensAfter` are present.
2. `estimatedTokensAfter < tokensBefore`; report the reduction fraction.
3. The retained raw tail is smaller than, and chronologically excludes, enough scored facts that exact recall cannot be solved from the tail alone.
4. The compacted state is non-empty and contains authoritative decisions/corrections rather than only stale setup text.
5. Recall is scored after compaction, including stale-value leakage.

If estimated size grows, quarantine the cell as insufficient-pressure even when recall is perfect. Correct by lowering only isolated model metadata plus reserve/tail settings, or by increasing the frozen transcript; do not silently reinterpret it as a successful compaction benchmark. Keep the provider/model endpoint unchanged.

For extensions that prepare memory incrementally, retain their normal trigger path. For controls, disable native auto-compaction and invoke one controlled manual compaction at the same boundary when supported. Label architectural differences rather than forcing unlike systems into a misleading single latency number.

## Timing

- Timestamp foreground manual compaction around the exact command.
- For background/prepared compaction, capture lifecycle start/end events. If events lack timestamps, report foreground latency as unavailable.
- Replace fixed sleeps with event-driven waiting plus a bounded timeout. Report any grace/calibration wait separately from end-to-end and foreground latency.
- A fast result with failed continuation fidelity is not a performance win.

## Multi-extension coexistence preflight

Before spending provider budget on a combined-extension variant:

1. Load the exact unmodified releases together in the real client, not only a mock registration harness.
2. Test both load orders when precedence could differ.
3. Inventory duplicate tool, command, shortcut, provider, and lifecycle-hook ownership. Client resource validation may reject duplicate names even when a lower-level runner documents first-registration precedence.
4. Record startup exit status and prove whether any provider work began.

If the client rejects the pair before provider start, report the combination as **not loadable** and cancel live quality cells. Do not silently rename, suppress, or wrap one extension: that creates a new custom candidate requiring its own pin, preregistration, security review, and benchmark.

## Post-blocker continuation

When the user asks to continue after a deterministic safety/correctness blocker:

1. Add a visible post-registration addendum naming the waived stopping rule, unchanged spend ceiling, and canonical remaining cells.
2. Preserve the blocker as a separate finding; do not rewrite the original preregistration.
3. Keep metrics and deployment recommendation distinct: a blocked candidate may still reveal a useful efficiency tradeoff.
4. Include all stopped, invalid, quarantined, and replacement provider work in inclusive cost/start counts.
5. Independently rescore canonical outputs, regenerate every aggregate/report, remove ephemeral auth and accidental stores, and generate checksums last.
