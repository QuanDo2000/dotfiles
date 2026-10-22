# Memory-extension ablations

Paths below are relative to this reference directory.

A default-on memory extension can affect every run without a visible memory-tool call. Separate and measure three exposure paths:

1. **Policy/context exposure:** fixed system-prompt policy text, prompt bytes/tokens, standing instructions, and recent-failure injection.
2. **Natural tool adoption:** memory search/write calls, returned context, errors, and whether recalled facts changed the answer or artifact.
3. **Persistence lifecycle:** startup/backfill, indexing, background review, session flush, database/RSS/process costs, and writes.

Do not interpret zero memory-tool calls as zero extension exposure. Compare enabled versus absent with identical unrelated instructions and project context, and report fixed prompt/context overhead separately from selected-tool overhead.

Use synthetic, source-grounded memory and session fixtures containing no real personal data or secrets. Include cross-session decision recall, durable preferences, environment/conventions, interruption continuity, stale/irrelevant-memory resistance, and normal tasks where memory should abstain. Score exact recall, provenance, harmful false recall, current-evidence precedence, artifact correctness, and abstention. Isolate the extension root and all stores per cell using the extension's supported agent-root/config override; never let a benchmark process write to live memory or session databases.

Before launching the matrix, inspect each candidate's actual path resolver and set every extension-specific store override; an agent-root override does not prove that a third-party extension follows it. Run one canary write, enumerate both the isolated root and every possible live default target, and reject the canary unless all created files are under the cell root. For compaction, require evidence that `estimatedTokensAfter < tokensBefore`, that the retained raw tail cannot contain all scored facts, and that recall depends on a non-empty/useful compressed state. A compaction event plus correct recall is insufficient when the raw tail survived. Fixed grace sleeps are calibration waits, not latency: wait on lifecycle events with a ceiling and report that wait separately.

Before benchmarking multiple extensions together, run an actual-client coexistence preflight in both load orders and inventory duplicate tool/command names. A mock loader or internal first-wins rule does not override client resource validation; if the released pair is rejected before provider start, mark it not loadable and do not manufacture metrics by silently renaming a tool. Treat any shimmed combination as a separately pinned candidate. See `memory-extension-compaction-and-isolation.md`.

If the user explicitly requests metrics after a safety blocker, preserve the blocker and stopping-rule violation in a post-registration addendum, keep the results out of the installation verdict unless explicitly waived, and retain all provider spend. See `memory-extension-compaction-and-isolation.md` for the validated isolation canary, pressure checks, quarantine, coexistence preflight, and recovery workflow. For the verified Pi Hermes Memory isolation boundary, see `pi-hermes-memory-ablation.md`.
