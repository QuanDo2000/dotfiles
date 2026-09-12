# Subagent runtime routing

Choose by ownership and lifecycle, then verify live state. Versions and defaults change; never infer from memory alone.

## Comparison

| Runtime | Best fit | Lifecycle | Main caveat |
|---|---|---|---|
| Main agent | tiny/serial work and final synthesis | current session | context pollution if used for huge raw inventories |
| Hermes `delegate_task` | bounded general reasoning with Hermes tools | background child in shared process | only final summary enters parent; not durable across owner-process loss |
| Pi native subagents | structured coding/research agents, chains, steering, worktrees | foreground or artifact-backed async | extension configuration owns timeout, wait, model, and concurrency semantics |
| Codex native subagents | code exploration, implementation, review, monitoring | Codex thread/app-server lifecycle | custom roles and routing depend on current Codex feature/config schema |
| Background Pi/Codex CLI | long independent coding mission | tracked subprocess | parent must inspect outputs/diff and manage process completion |
| Kanban/cron | durable multi-worker or scheduled work | persisted queue/scheduler | higher orchestration overhead; use only when durability/retry is required |

## Hermes checks

```bash
hermes config get delegation
```

Inspect live task records under:

```text
$HERMES_HOME/cache/delegation/live/<delegation-id>/
```

Current Hermes behavior uses no hard child timeout when `child_timeout_seconds` resolves to `0`. The heartbeat staleness monitor and iteration budget remain separate controls.

When Hermes uses the optional Codex app-server runtime, `delegate_task`, `memory`, `session_search`, and Hermes `todo` are unavailable because they require the Hermes agent loop. Use Codex-native agents there, or switch Hermes back to its default runtime for Hermes delegation.

## Pi checks

```bash
pi --version
pi list
```

For an existing Pi process inside tmux, list and capture its pane before sending input. If plain `tmux list-sessions` reports no server, do not assume none exists: Hermes' shell may lack the user's `TMUX_TMPDIR`/runtime environment. Check the running tmux command and sockets under `/run/user/$UID/tmux-$UID/`; then address the discovered server explicitly, for example:

```bash
tmux -S /run/user/$UID/tmux-$UID/default list-panes -a
tmux -S /run/user/$UID/tmux-$UID/default capture-pane -p -t session:window.pane -S -40
tmux -S /run/user/$UID/tmux-$UID/default send-keys -t session:window.pane 'message' Enter
```

Capture again after sending. Never send input until the pane and current task are identified.

Inspect:

```text
$PI_CODING_AGENT_DIR/settings.json
$PI_CODING_AGENT_DIR/extensions/subagent/config.json
```

For `pi-subagents`, distinguish run deadlines from waiting:

- `timeoutMs`/`maxRuntimeMs` can impose a run deadline.
- A foreground run may have a runtime default supplied by the extension.
- Async work may continue after the parent yields.
- `subagent_wait` timing out stops the wait; it does not prove the child was killed.
- Verify async `status.json`, `events.jsonl`, output log, result JSON, and completion notification.

Useful configuration fields include async default, compact tool descriptions, artifact location, global concurrency, per-session spawn cap, model scope, and per-agent model/thinking overrides. Read their resolved values; do not hardcode another installation's choices.

## Team-size and concurrency caps

Translate total team size before editing config: **N total agents = one parent + N-1 children**. Keep concurrency, per-call task count, nesting depth, and cumulative session spawns separate.

Hermes uses:

```bash
hermes config set delegation.max_concurrent_children <N-1>
hermes config get delegation.max_concurrent_children
```

A running Hermes session can retain the old generated `delegate_task` schema, so verify the persisted value and confirm the new limit in a fresh session.

Pi Subagents keeps native orchestration config separate from Pi's main `settings.json`:

```json
{
  "globalConcurrencyLimit": 7,
  "parallel": {
    "maxTasks": 7,
    "concurrency": 7
  }
}
```

Use the same N-1 value for all three fields: `maxTasks` bounds children accepted by one parallel call, `parallel.concurrency` bounds that call's simultaneous work, and `globalConcurrencyLimit` bounds simultaneous tasks within one subagent run. `maxSubagentSpawnsPerSession` is a cumulative launch budget, not a concurrency cap; do not lower it just to express team size.

Pi's native global limit is documented **per run**. Overlapping independent async runs can exceed it in aggregate. If the requirement is a strict session- or machine-wide cap, avoid overlapping runs or add an explicit outer coordinator rather than claiming the per-run setting provides that guarantee.

For declarative dotfiles, manage `$PI_CODING_AGENT_DIR/extensions/subagent/config.json` as a writable seeded file using the existing three-way merge mechanism. Do not symlink application-editable runtime config directly into the read-only Nix store. Build the intended host profile, apply it, then compare live and seed values.

## Codex checks

```bash
codex --version
codex features list
codex doctor
```

Confirm `multi_agent` state, auth/network health, thread DB consistency, and whether project/user `.codex/agents/*.toml` roles exist. Absence of custom roles means built-in/default routing, not a broken multi-agent system.

Codex-native agents are not Hermes `delegate_task` children and do not inherit Hermes delegation timeout settings. For a long one-shot launched by Hermes, use a tracked background terminal process, an explicit workdir, one writer per worktree, and parent-side diff/test verification.

## Dispatch recommendations

- Prefer Pi when its configured chains, fleet view, steering, async artifacts, or worktree workflows materially help.
- Prefer Codex for focused code-native implementation/review under its sandbox and role system.
- Prefer Hermes for short general-purpose lanes needing its broader tools and automatic result delivery.
- Do not nest runtimes merely because nesting is possible. `Hermes → Pi/Codex process → native children` is justified only for a long mission that benefits from the external runtime's orchestration.
