# Cross-runtime A2A setup

Use this reference when connecting independent agent runtimes through Agent2Agent rather than native in-process delegation.

## Decide before installing

1. Identify each direction separately: runtime A calling B and B calling A may require different client/server components.
2. Explain what receives an inbound task. A bridge may spawn a fresh isolated session rather than continue the user's visible interactive conversation.
3. State workspace and tool authority. An inbound coding-agent session can become another repository writer even when the network transport is localhost-only.
4. Compare the native alternative. For same-machine work, in-process subagents or supervised tmux usually preserve context and ownership with less machinery.
5. Review third-party executable code before installation: package manifest, source/repository match, declared and resolved dependencies, install scripts, bind defaults, authentication gates, credential storage, injection filtering, outbound redaction, anti-loop limits, audit logs, and maintenance activity.
6. Trace vulnerability findings to dependency paths. Do not attribute advisories from a shared package root to the new bridge without `npm explain`/equivalent evidence.
7. Present findings and receive explicit informed approval before running the package installer. Selection or setup discussion alone does not authorize installation.

## Safe local staging

Prefer the smallest reversible configuration:

- bind both inbound servers to loopback;
- do not configure LAN/public exposure, mDNS, reverse proxies, or tokens unless required;
- add only the two explicit peer URLs;
- avoid global inbound auto-start when every interactive session would open a server or choose fallback ports;
- start the server only in the intended session/workspace;
- preserve one-writer-per-worktree policy;
- reload/restart only after config inspection, and state which current sessions retain startup state.

A loopback bind prevents remote access but does not authenticate local processes. Treat any local caller as capable of submitting untrusted tasks. If remote access is required, add per-peer credentials before widening the bind address.

## Bidirectional verification

1. Confirm the intended processes loaded their extensions after restart/reload.
2. Verify each listener is bound to the expected loopback address and port.
3. Fetch both Agent Cards and confirm advertised URLs and capabilities.
4. Send one bounded read-only task A → B and one B → A.
5. Confirm each response came from the intended runtime and workspace, not merely that HTTP returned success.
6. Inspect task/audit records and confirm no repository changes occurred during the smoke test.
7. Only then permit mutation-capable tasks.

If the user's correction arrives after installation but before activation, stop. Report package registration, configuration changes, loaded-process state, and listeners separately. Do not silently finish or uninstall; either direction is another state change requiring the user's decision.