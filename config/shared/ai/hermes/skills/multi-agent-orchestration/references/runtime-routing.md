# Runtime Routing

Choose by ownership/lifecycle, then inspect the installed runtime. Defaults, APIs, and available extensions change.

| Mechanism | Use when | Boundary |
|---|---|---|
| Main agent | tiny, serial, tightly coupled work or synthesis | do mechanical inventory with local tools |
| Hermes `delegate_task` | an isolated general reasoning lane needs Hermes tools | only final summary enters parent; owner-process loss can lose handoff |
| Pi subagent extension | installed chains, steering, worktrees, or async artifacts help | extension owns lifecycle/model/concurrency semantics; not a core Pi guarantee |
| Codex native agents | code-native exploration, implementation, review, monitoring | feature/config and role support must be verified |
| Tracked background CLI | a bounded mission outlives the current turn | explicit workdir/ownership, output and process supervision; not durable |
| Kanban/cron | work must survive resets, retry, or deliver later | persisted ownership/retry/delivery, with extra overhead |

Do not nest runtimes unless their distinct capabilities justify it. Native delegation or supervised tmux is usually simpler for same-machine work.

## Hermes

Inspect `hermes config get delegation` and live task records at `$HERMES_HOME/cache/delegation/live/<delegation-id>/`. Verify the resolved timeout and iteration/heartbeat controls separately.

Hermes' optional Codex app-server runtime does not expose Hermes-loop tools such as `delegate_task`, `memory`, `session_search`, and Hermes `todo`. Verify the active runtime rather than inventing calls.

For a requested total team size N, children are N−1. Hermes' `delegation.max_concurrent_children` is distinct from iteration/spawn budgets; after an authorized change, verify persisted config and a fresh session's generated tool schema.

## Pi

Inspect `pi --version`, `pi list`, live settings, project overrides, and installed extension source. Do not assume Pi Subagents exists just because these references describe it. If installed, its runtime config may live at `$PI_CODING_AGENT_DIR/extensions/subagent/config.json`; verify the active schema before changing it.

Use `pi-concurrency-and-model-scope.md` for concurrency lifetime and deployment safeguards, and `pi-model-routing.md` for effective selection. Run deadlines, parent waits, per-run limits, and session-wide caps are different contracts; inspect async status, events, logs, result artifacts, and completion notification.

For an existing tmux agent, follow `pi-tmux-agent-operations.md`; identify the socket, pane, and current task before sending input, then verify delivery.

## Codex

Use the installed CLI's supported feature/health commands and inspect project/user role configuration. Missing custom roles can mean built-in routing, not a broken system. Check auth/network health without exposing secrets.

Codex-native agents do not inherit Hermes delegation timeouts. For external CLI missions, use a tracked process, explicit workdir, one writer per worktree, and parent-side diff/test verification.
