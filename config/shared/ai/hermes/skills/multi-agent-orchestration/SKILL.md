---
name: multi-agent-orchestration
description: "Use when routing work across subagent runtimes."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [delegation, subagents, orchestration, codex, pi, debugging]
---

# Multi-Agent Orchestration

Use this skill to choose between inline work, Hermes delegation, Pi/Codex-native subagents, external agent processes, and durable workers; to design bounded fan-outs; and to diagnose timeout or missing-summary failures.

## Selection ladder

Stop at the first mechanism that fits:

1. **Main agent:** tiny, serial, or tightly coupled work.
2. **`execute_code`:** mechanical inventory, counting, filtering, schema extraction, or bulk reduction that does not need judgment.
3. **Hermes `delegate_task`:** one bounded reasoning lane that benefits from isolated context and can return a concise summary.
4. **Pi native subagents:** structured coding/research fan-outs, chains, steering, worktrees, and inspectable async artifacts inside Pi.
5. **Codex native subagents:** code-centered exploration, implementation, review, and monitor roles inside Codex.
6. **Background CLI process:** a long Pi/Codex/Hermes mission that should be tracked independently from the current agent turn.
7. **Kanban or cron:** durable work that must survive session/process loss, coordinate writers, retry, or deliver later.

Do not delegate work merely to appear parallel. Independent substantial lanes justify fan-out; tiny, duplicate, or strictly serial tasks do not.

## Dispatch contract

Every child receives only what it needs:

- one outcome-oriented goal;
- exact workspace and source paths;
- relevant observed errors/state, because children know no parent history;
- one reasoning lane, not an exhaustive whole-system audit;
- explicit exclusions and side-effect boundary, including the only writable root;
- stop criteria or a practical call/turn ceiling;
- exact output shape and evidence requirements.

When a child may inspect a live repository but must write elsewhere, record the repository's pre-dispatch status and tell it that the live tree is read-only. Recheck status while it runs and after completion. A prose boundary is not verification: if the child writes outside its assigned root, stop using its side effects, preserve only useful evidence, and restore only changes attributable to that child. Never merge incidental fixes into the requested task merely because they appear reasonable.

For read-only reviewers—especially those without shell/Git tools—include the changed-file list, complete diff or readable diff artifact, deleted-file contents needed for parity review, and validation evidence in the initial dispatch. If they request missing evidence through supervisor intercom, reply to and recover the same detached run; do not launch a replacement while it remains recoverable. See `references/reviewer-evidence-handoffs.md`.

For a broad investigation, let the parent mechanically precompute inventories, then delegate narrow runtime, algorithm, review, or validation lanes. The parent owns synthesis and verifies file writes, external changes, URLs, IDs, tests, and process state.

## Parallel safety

- One writer per worktree. Parallel readers may share a workspace; parallel writers may not.
- Split by independent evidence source or ownership boundary, not arbitrary file ranges.
- Do not make two children rediscover the same inventory, reload the same large logs, or both synthesize the final answer.
- Use the cheapest capable child model; reserve stronger models for ambiguous strategy, adversarial review, or synthesis.
- Prefer async/background launches when the parent can continue useful work. Wait only when the current step truly depends on the child result.

## Timeout diagnosis

Treat these as distinct:

1. **Run wall-clock timeout:** kills the child and can discard an otherwise useful final summary.
2. **Wait timeout:** stops waiting while background work continues.
3. **Iteration/tool/usage budget:** bounds work units and should encourage a final summary before exhaustion.
4. **Provider request timeout or stalled call:** one API request stopped progressing.
5. **Process/session lifetime:** parent reset or process exit may orphan or cancel non-durable work.

A child with successful tool activity immediately before a fixed-duration cutoff was not hung; the wall-clock policy was wrong for the task. Inspect live transcripts and durable artifacts before re-dispatching or declaring the child useless. Salvage evidence once, then narrow the next task.

For Hermes delegation, prefer the current no-hard-cap default and heartbeat/iteration controls. A positive `delegation.child_timeout_seconds` is an intentional unattended-cost control, not a general reliability default. See `references/delegation-timeout-diagnosis.md`.

## Runtime boundaries

- **Hermes:** general tools and fresh isolated reasoning; only final summaries enter the parent context. Live transcripts are the failure-recovery record. `delegate_task` is unavailable inside Hermes' Codex app-server runtime because it requires Hermes agent-loop state.
- **Pi:** its subagent extension owns agent profiles, async lifecycle, wait semantics, chains, worktrees, and artifacts. A wait timeout must not be mistaken for child termination.
- **Codex:** native multi-agent roles are separate from Hermes delegation. Verify live feature/config state before assuming custom roles, model routing, concurrency, or timeout behavior.
- **External processes:** use tracked background processes for long bounded CLI missions; use Kanban/cron when execution itself must be durable.

### Third-party runtime bridges

Before installing an agent bridge or protocol extension, explain the candidate package, directionality, real session semantics, dependency/code-execution footprint, network exposure and authentication, lifecycle/reload impact, workspace/write authority, and simpler native alternatives. Then obtain explicit informed approval for installation. A request to evaluate or understand packages is not installation approval; do not race ahead while presenting the review. If a sequencing correction arrives after a side effect, stop immediately, disclose the exact current state, and wait before either continuing or rolling back.

For cross-runtime A2A, distinguish calling the visible interactive session from spawning an isolated agent session. Same-machine work should normally use native delegation or supervised tmux unless process/framework isolation is the actual requirement. See `references/a2a-cross-runtime-setup.md`.

See `references/runtime-routing.md` for the compact comparison and live verification commands.

## Conditional investigations

For model/provider changes, load `references/hermes-model-routing.md` or `references/pi-model-routing.md`; inspect main, child, auxiliary, and fallback routing separately.
For Pi concurrency or scope enforcement, load `references/pi-concurrency-and-model-scope.md`; distinguish declarations from observed runtime limits.
For failed batches, use `references/delegation-timeout-diagnosis.md` for counts, last activity, scope, and evidence-versus-handoff utility.
For role removal, use `references/subagent-portfolio-audit.md` for transcript analysis, reversible changes, and re-measurement.
Use one reviewer by default; add another only for a named distinct risk. Diagnose orchestration waste before removing a useful role.

## Verification checklist

Before declaring orchestration healthy:

1. Run one small bounded smoke child with exact sources and output shape.
2. Confirm it obeyed scope and produced the requested summary.
3. Confirm runtime configuration resolves to the intended timeout/budget policy.
4. For async work, verify the completion artifact and notification, not merely process disappearance.
5. For edits, inspect the diff and run the smallest relevant check.
6. For durable workflows, verify ownership, retry state, and final delivery.

## References

- `references/delegation-timeout-diagnosis.md` — transcript-led timeout triage and the 600-second watchdog case.
- `references/runtime-routing.md` — Hermes vs Pi vs Codex vs durable-worker selection and live checks.
- `references/hermes-model-routing.md` — layered Hermes model selection, fallback-auth audit, CLI changes, and verification.
- `references/pi-model-routing.md` — Pi main/subagent precedence, provider scope, model availability, auth, and managed-state verification.
- `references/a2a-cross-runtime-setup.md` — informed package review, runtime semantics, secure staging, and bidirectional verification for A2A bridges.
- `references/reviewer-evidence-handoffs.md` — evidence packets and recovery for restricted read-only reviewers.
