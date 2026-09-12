# Pi model-routing audit

Use this when reviewing or changing Pi's main model, native subagent roles, reasoning levels, provider scope, or model availability.

## Audit the live and declarative layers

Inspect both the writable live settings and any managed seed that deploys them. Treat application-owned fields such as `lastChangelogVersion` as runtime state, not configuration drift.

Check for project-local overrides before interpreting the global file. Pi Subagents resolves nearest project settings above user settings, so inspect the working tree for `.pi/settings.json` and custom agent directories as well as `~/.pi/agent/settings.json`.

Safe runtime probes:

```bash
pi --version
pi --list-models <model-family-or-pattern>
pi auth check --provider <provider> --json --no-refresh
```

Do not use credential-printing flags or read raw auth stores. Confirm every selected model appears in `--list-models`, including context, output, thinking, and image capabilities.

## Resolve effective selection correctly

Treat the main session and subagents separately:

1. **Main session:** `defaultProvider`, `defaultModel`, and `defaultThinkingLevel`; command-line/session selections can override these defaults.
2. **Built-in role frontmatter:** each shipped role may already define a thinking level or model.
3. **`subagents.defaultModel` / `defaultThinking`:** defaults fill only missing role fields; they do not replace explicit built-in values.
4. **`subagents.agentOverrides.<role>`:** per-role model/thinking overrides apply after defaults and win.
5. **Invocation override:** a task-level model or thinking request wins for that launch, subject to model scope.
6. **Project settings:** nearest project configuration wins over user configuration where supported.

This means a global `defaultThinking` can be inert for all current built-ins while still affecting future custom roles. Build the effective role table from the shipped role definitions plus settings; do not report the defaults as if every role inherited them.

## Provider and fallback boundaries

- `subagents.modelScope.enforce` constrains the models children may launch; verify the allowlist before assuming a requested override works.
- Pi authentication is independent of Hermes authentication status even when both use the same provider name.
- Hermes fallback providers do not automatically become Pi or Pi-Subagents fallbacks. Audit role `fallbackModels` and Pi-native provider behavior separately.
- A model being named in settings does not prove availability; pair settings inspection with `pi --list-models` and an auth readiness check.

## Review heuristics

- Reserve stronger models and high reasoning for synthesis, ambiguous strategy, or adversarial review.
- Avoid maximum reasoning for routine scouting, bounded implementation, or mechanical delegation unless measured quality requires it.
- Distinguish role specialization from cost tier: researcher/reviewer frontmatter may intentionally choose different reasoning despite sharing a default model.
- Note redundant or compatibility role overrides, but verify runtime discovery before deleting them.
- Existing or resumed sessions may retain their prior main model and reasoning; validate persistent defaults in a fresh session.

## Verification after changes

1. Re-read the live settings and declarative seed.
2. Confirm no unintended project-local override wins.
3. Recompute the effective model/reasoning table using the precedence above.
4. Run `pi --list-models` and `pi auth check` without exposing credentials.
5. If availability or role resolution remains uncertain, run one bounded fresh-session smoke child and inspect its recorded model metadata.
6. Verify the managed seed still deploys without clobbering legitimate runtime-owned state.
