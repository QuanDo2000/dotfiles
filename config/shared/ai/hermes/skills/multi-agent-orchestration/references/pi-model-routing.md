# Pi Model Routing

Use when auditing or changing Pi's main model or an installed subagent extension. Pi core and extension settings are separate contracts; do not assume a subagent package or role schema exists.

## Inspect effective selection

- Check the installed version, package list, writable live settings, managed seed, and applicable project overrides. Runtime-owned fields are not automatically configuration drift.
- For the main session, inspect `defaultProvider`, `defaultModel`, and `defaultThinkingLevel`, then account for CLI/resumed-session overrides.
- If a subagent extension is installed, read its current resolver and role definitions. Determine precedence among role frontmatter, defaults, per-role overrides, invocation overrides, and project settings; defaults may only fill missing fields. Do not copy historical configuration keys without checking the active schema.
- Audit fallback models and model-scope enforcement separately. Determine whether an out-of-scope selection rejects or merely warns, including inherited and fallback selections. Routing controls are not a security sandbox.

Use `pi --list-models <pattern>` to check advertised capabilities and the installed CLI's supported auth-readiness check without printing credentials. Catalog/config presence is not proof that a provider request succeeds. Pi auth and fallbacks are independent of Hermes, even for similarly named providers.

## Change and verify

Choose the cheapest capable model for each lane; stronger reasoning needs a task-specific reason. Preserve runtime-owned settings and existing seed-merge ownership. Change only authorized routing, not credentials or unrelated defaults.

Re-read live and declarative settings, recompute effective selection, and verify no unintended project override wins. If model availability or role resolution is uncertain, run one bounded fresh-session smoke and inspect recorded model/reasoning metadata. Existing sessions may retain startup selections. Report configured versus exercised behavior separately; use `pi-concurrency-and-model-scope.md` when concurrency or hard policy enforcement matters.
