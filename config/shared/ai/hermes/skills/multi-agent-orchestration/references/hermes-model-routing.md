# Hermes Model Routing

Audit main, child, auxiliary, and fallback routing independently; the active model name alone does not identify the effective configuration.

## Inspect

Use the installed Hermes CLI to read `model`, `agent.reasoning_effort`, `agent.reasoning_overrides`, `delegation`, and `auxiliary`; inspect `hermes fallback list` and run `hermes config check`. Never print secrets or raw auth stores.

- Main selection combines model and provider; a matching per-model reasoning override wins over global effort.
- Delegation has independent model/provider/reasoning settings; inspect whether children inherit the main fallback chain.
- Auxiliary tasks (compression, titles, vision, approvals, monitors) have separate routing. `provider: auto` may resolve to the main model rather than a cheaper side model.
- A configured fallback may remain after logout. Use `hermes auth status <provider>` to check readiness, not the mere presence of an entry.

## Change

Use `hermes config set <key> <value>` for approved changes instead of hand-editing YAML. Choose the cheapest capable model and effort for the specific lane; do not assume compression or title generation needs maximum reasoning. Do not change credentials or fallback policy without authorization.

`hermes fallback remove` is interactive: select only the approved entry, not the whole chain. Dynamic reasoning-override keys may emit an unknown-key notice despite saving; inspect the resolved map before interpreting the result.

## Verify

Re-read the affected layers and run `hermes config check`; confirm effective overrides, auxiliary resolution, and remaining fallback readiness. If model availability or delegation resolution is uncertain, run one bounded smoke child. Validate persistent main defaults in a fresh session because existing sessions may retain startup state.

Distinguish configuration, auth readiness, and successful inference. Cross-provider fallback can change tool behavior and lose prompt-cache continuity; do not call an unusable fallback resilience. Authenticate or remove it only within the approved scope.
