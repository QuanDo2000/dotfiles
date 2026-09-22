# AI Code-Search Stack Audit

Use this when dotfiles manage an editor plugin, agent extension, or MCP server for code search/navigation.

## Audit four layers

1. **Declarative source** — package pin, Home Manager/module declaration, client config seed, shell/session variables, and platform-specific installer.
2. **Deployed state** — resolve the live executable and live client config. A correct seed does not prove an existing writable config received later additions.
3. **Protocol surface** — start the exact built/deployed server through an MCP inspector and enumerate tool schemas. `--help` and a successful process start do not prove the client can discover every tool.
4. **Feature state** — inspect runtime configuration and optional databases. A health check may exit zero while reporting optional ranking/history stores as unresolved or disabled.

## FFF-style search stacks

- Verify filename search, content search, and multi-pattern search independently.
- Check editor, CLI/MCP, and agent-extension versions separately; they can drift even when they share an upstream release.
- Frecency and query history generally require explicit database paths. If several clients should learn from the same usage, give them the same stable paths through environment variables.
- When an MCP client does not expand `$HOME` inside argument arrays, use one tiny managed wrapper that resolves the paths and `exec`s the real server.
- Run the server health check with the configured database paths. Treat “all checks passed” plus “path not resolved” as partial capability, not full configuration.

## Knowledge-graph MCP stacks

- Inspect `config list`; automatic watching and automatic initial indexing are separate settings.
- Confirm the selected package variant preserves optional UI features when replacing a source-built package with a prebuilt release.
- Enumerate MCP schemas and smoke-test high-value read tools: project listing, indexing/status, architecture, graph search, path tracing, snippets, and change-impact analysis.
- Auto-approve only read-only/cache-building tools. Leave deletion, ADR mutation, trace ingestion, and other state-changing tools gated.
- Keep global agent guidance short: name the preferred structural tools, a raw-text fallback, and a pre-finalization change-impact check. Tool schemas carry the detailed feature tour.

## Writable client-config seeds

- Treat a tracked seed as a declarative overlay: recursively apply tracked keys to the live config while retaining live-only keys needed by the client.
- If live-only additions are promoted back into the tracked seed, exclude application-owned runtime sections such as hook trust state.
- Write both tracked and live TOML/JSON atomically, then parse the result before activation succeeds.
- Leave two regression checks: live-only nested settings survive, and newly tracked MCP sections appear in the deployed live file. Always inspect that live file after activation.

## Nix verification

- Hash-pin release assets per supported platform and build every flake output used by CI.
- If the flake references a new untracked package file, stage only that file for the build and report the staged state.
- Build the Home Manager activation package before switching. After switching, re-check live versions, live client registration, MCP tool discovery, optional database health, and the final worktree state.
