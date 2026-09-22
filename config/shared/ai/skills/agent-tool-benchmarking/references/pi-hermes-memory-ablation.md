# Pi Hermes Memory benchmark isolation

For `pi-hermes-memory` v0.9.7, isolate each benchmark cell with `PI_CODING_AGENT_DIR=<cell-agent-root>`. `src/paths.ts` resolves the extension agent root from this variable before falling back to `~/.pi/agent`.

The default `policy-only` mode still exposes the extension without a tool call:

- `before_agent_start` appends the memory policy to the system prompt;
- standing instructions and eligible recent failures may inject context;
- ordinary `MEMORY.md` and `USER.md` facts generally require natural `memory_search` selection.

Record policy/injected-context bytes separately from memory-tool calls. Seed only synthetic stores under the isolated agent root. Hash live Pi settings and memory/session stores before and after; no benchmark process should open them writable.

## Orchestrator isolation

Isolation applies to the supervising agent too, not only benchmark children. While the benchmark is active, the orchestrator must not call live memory write/remove/consolidation tools to record benchmark state or decisions. Persist orchestration notes under the benchmark artifact root instead. If live memory was mutated, restore visible content when possible, preserve an incident audit, and report a constraint exception: matching visible text or character usage does not prove SQLite row IDs, timestamps, or metadata are unchanged.

## Workload-frequency decision rule

A coverage-balanced matrix is not a production frequency model. Report per-stratum effects before the aggregate verdict, then apply the user's real task distribution and stated priorities. In particular, strong gains on decision recall, preference recall, or session continuity can justify default-on memory for a user who relies on past sessions frequently, even when a balanced synthetic suite favors on-demand loading due to startup, RSS, or token overhead. If usage frequency is unknown, make the default-on recommendation conditional rather than categorical.
