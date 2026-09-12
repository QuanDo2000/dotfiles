# Hermes model-routing audit and changes

Use this when selecting separate models for the main agent, delegated children, auxiliary tasks, and provider fallbacks.

## Audit before changing

Read the resolved configuration rather than inferring it from the active model name:

```bash
hermes config get model
hermes config get agent.reasoning_effort
hermes config get agent.reasoning_overrides
hermes config get delegation
hermes config get auxiliary
hermes fallback list
hermes auth list
hermes config check
```

Interpret the layers separately:

1. **Main model:** `model.default` + `model.provider`.
2. **Main reasoning:** a matching `agent.reasoning_overrides` entry wins over global `agent.reasoning_effort`.
3. **Delegation:** `delegation.model`, provider, and reasoning are independent of the main model; children may inherit the main fallback chain.
4. **Auxiliary tasks:** vision, compression, titles, approvals, monitors, and other side calls each have independent routing. `provider: auto` can resolve back to the main model, so review it before assuming side calls are cheap.
5. **Fallbacks:** entries can persist even when their provider is logged out. `hermes fallback list` shows configuration; `hermes auth status <provider>` verifies usability.

Do not display secrets from config or auth stores.

## Apply the smallest change

Use Hermes' CLI rather than hand-editing YAML:

```bash
hermes config set agent.reasoning_overrides.<normalized-model> medium
hermes config set delegation.model <model>
hermes config set delegation.reasoning_effort medium
hermes config set auxiliary.title_generation.model <model>
hermes config set auxiliary.title_generation.reasoning_effort medium
hermes fallback remove
```

`hermes fallback remove` is interactive; select the exact dead entry rather than clearing the chain. Dynamic map keys such as `reasoning_overrides.<model>` may produce an unknown-key notice even when saved; verify the resolved map instead of assuming the notice means failure.

## Verification

```bash
hermes config get model
hermes config get agent.reasoning_overrides
hermes config get delegation
hermes config get auxiliary.title_generation
hermes fallback list
hermes auth status <remaining-provider>
hermes config check
```

Confirm the effective main reasoning is the per-model override, not merely the global default. Run a small bounded delegation smoke test when model availability itself is uncertain. Persistent defaults may not rewrite an already-running session's startup state; use a reset/new session when validating the new main selection.

## Selection heuristics

- Keep synthesis and final verification on the strongest model needed.
- Use a cheaper capable model for bounded child work, but do not force maximum reasoning on trivial lanes.
- Compression needs continuity more than maximum reasoning.
- Title generation rarely needs high reasoning.
- A configured but unauthenticated fallback is not resilience; authenticate it or remove it.
- Cross-provider fallback preserves the turn but can change tool behavior and loses prompt-cache continuity.
