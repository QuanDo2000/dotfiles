# Hermes native delegation A/B adapter

Use this when adapting a production-shaped subagent benchmark to Hermes `delegate_task`.

## Controlled variants

1. Pin the installed Hermes version, model, provider, reasoning level, repository revision, and frozen workload/rubric.
2. Create an isolated `HERMES_HOME` template from the production configuration and non-secret context.
3. Variant A retains the normal CLI toolsets. Derive B from A with:

```bash
HERMES_HOME="$variant_b" hermes tools disable delegation --platform cli
```

Do not hand-edit `config.yaml`. Keep all other toolsets and context identical. Prove the fresh-session difference offline with `hermes prompt-size --platform cli --json` and `hermes tools list`: A must expose `delegation`, B must not, and the schema/tool count delta must be exactly the delegation tool. Compare A to B under the same isolated auth state; conditionally registered tools such as vision can make an unauthenticated isolated template differ from the live process without invalidating the A/B diff.

## Invocation and isolation

Use one-shot mode with an atomic usage sidecar:

```bash
HERMES_HOME="$cell_home" hermes \
  --usage-file "$cell_home/usage.json" \
  --provider "$provider" -m "$model" --reasoning "$level" \
  -z "$prompt"
```

Each cell gets a fresh mode-700 home and disposable Git worktree. If the user approved live OAuth transport, copy only `auth.json` as mode 600; never read, log, hash, diff, or archive it. Delete it before preserving the cell home and on every failure path. Verify live auth metadata and repository cleanliness before and after every cell.

## Inclusive accounting

Hermes stores canonical session telemetry in `$HERMES_HOME/state.db`:

- `sessions.parent_session_id IS NULL` identifies the parent;
- non-null `parent_session_id` identifies delegated children;
- sum input, output, cache-read, cache-write, reasoning, and API-call fields across parent and child session rows;
- parse assistant `messages.tool_calls` JSON for per-tool counts and `delegate_task` arguments;
- classify `delegate_task` with omitted/`spawn` action as spawn calls and `list`/`steer`/`stop` as lifecycle calls;
- count batch `tasks` entries separately from spawn-tool invocations.

The one-shot usage file's `estimated_cost_usd` already includes child cost when Hermes has a priced route because it rolls child spend into the parent. **Do not add child session costs again.** Treat `estimated_cost_usd: 0` with `cost_source: none` as **monetary cost unavailable**, not free execution and not a zero-dollar projection. Parent token and API counters are not the inclusive child total, so derive inclusive token/API metrics from all linked session rows. A practical inclusive-token total is `input + cache_read + cache_write + output` across parent and children; keep reasoning separate when it is already represented within output accounting. Preserve the state database after removing auth, and independently reparse it during final verification.

## Native subscription-allowance telemetry

When authorization permits native saved-login use but forbids credential copies, use the existing client resolver and its normal refresh path; do not reuse the auth-copy adapter above. Preserve raw usage and catalog response bodies without request headers or auth fields. Reject catalog fallback/synthetic additions as entitlement evidence. Block alternate-account recovery or pool fallback in the probe when account rotation is prohibited.

Identify quota windows from provider duration metadata, not primary/secondary position: a primary window can be weekly with a null secondary. Never substitute a separate model-specific short-window quota for the general models. A missing account header is not evidence of different accounts, but does not independently prove account binding. Record small reset-timestamp drift as possible jitter, not as proof of redemption; do not silently invent a tolerance for an exact-reset gate. A fresh HTTP Date proves transport freshness, not bounded consumption-meter lag. Under a user-approved soft allowance guard, do not resurrect a hard-no-overshoot prerequisite; stop on genuinely missing or ambiguous required telemetry instead.

## Budget gate

Before calibration, obtain explicit approval for the exact auth-copy method and a calibration ceiling. Before every cell, persist a projection using the larger of a conservative reference and observed per-workload maxima. Calibration authorizes calibration only; freeze a separate full-matrix ceiling and exact authorization marker after projected cost is known.

A concurrent monitor must inspect only fixed cell-state paths. Do not recursively glob a live run root: disposable worktree deletion can race `pathlib` traversal and crash the monitor. Treat the runner's atomic checkpoints as authoritative; a monitor alerts on stops and inconsistencies but must not blindly restart a partial provider call.

If the OAuth/provider route emits no monetary estimate, switch the canonical gate to inclusive parent-plus-child tokens rather than manufacturing prices from another client or model. Report monetary cost as unavailable. Project the full matrix from per-workload inclusive-token maxima, obtain approval for that exact token ceiling, and before each canonical cell recompute:

```text
used valid-cell tokens
+ excluded-attempt tokens
+ remaining cells × max(pilot workload maximum, observed canonical workload maximum)
```

Persist the gate before stopping. A calibration report that multiplies zero-valued `cost_source: none` estimates into a `$0` full projection is invalid and must be corrected before requesting canonical approval.
