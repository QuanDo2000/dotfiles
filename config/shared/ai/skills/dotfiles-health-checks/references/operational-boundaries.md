# Additional Operational Boundaries

These constraints accompany the topic procedures, not every health check. Governing policy remains authoritative.

## Instructions, skills, and mutable settings

- Resolve tracked versus machine-local ownership before editing. Reproducible changes require tracked sources and platform installation wiring; preserve complete assets, provenance, and harness-specific adaptations. Local-only changes are not cross-machine deployment.
- Protected instruction edits belong in the foreground approval path. A delegated noninteractive denial is not proof the user rejected a visible prompt. After denial/timeout, stop; retry only with renewed authorization through the same gate, not another writer or disabled protection.
- Distinguish fixed startup policy from genuinely switchable/stop behavior. Remove only redundant wrappers; preserve distinct conditional workflows and ignored runtime catalog state. Descriptions specify triggers, bodies specify procedure.
- Back up existing directories before non-forcing managed-link activation. Compare complete deployed trees, verify each skill is discovered once and references load, and test fresh-session/child semantics. Explicitly remove retired copy-based Windows hooks/skills; deleting tracked source alone does not uninstall them.
- Test updater durability in temporary fixtures, never live skills: fresh/existing manifests, multiple upstream revisions, managed symlinks, and an unmanaged sentinel. Preserve links/bytes, reject unknown update modes, and record manual ownership plus upstream revision/license for adaptations. Forced reinstall/reset remains outside ordinary-update guarantees.
- Snapshot mutable tracked seeds around activation. Require an actual diff before claiming backwrites; preserve live-only preferences and remove only proven unrelated hook-induced hunks under authorization. Authoritative safety limits must not merge runtime changes back into policy.
- Before deleting a setting, inspect effective defaults. Keep explicit `false` if omission enables the feature, across every platform seed. Distinguish retired integration references from similarly named native features and negative/migration tests.
- Compare generation closures and resolved `home-path`/`home-files` for activation-only repairs. Identical paths can establish no package/file upgrade. Use the role-aware helper without bypassing guards.
- Configuration assertions prove stored values, not runtime enforcement. Inspect every launch path before claiming a session-global concurrency cap; report per-run limitations accurately.

## Package ownership and removal

- Distinguish distro base/meta-package guarantees, independent bootstrap requirements, and residual host installations. Under a distro-shipped-only policy, repository availability and unrelated reverse dependencies are insufficient. Never add a bootstrap package solely to remove its managed equivalent; preserve independently necessary prerequisites.
- Scope native fallback to the proven host capability, retaining managed packages elsewhere. Hide the managed executable in an isolated real consumer trial before switching. For fonts, verify package ownership, family/style counts, `fc-list`/`fc-match`, and retired closure absence. For shells, verify the account shell separately from `PATH`, versions/features, login/interactive startup, plugins, and completions.
- Trace each removal to concrete consumers: editor server IDs to commands, direct CI tools and LSP subprocesses, system/Mason/project/residual owners, active processes, services, cron, scripts, reverse dependencies, and install reason. A configured server name or ambient binary alone proves neither use nor orphanhood.
- Test the executable/interpreter actually invoked. A working system entry point and failing ambient `python -m` may simply have different owners. For test-runner retirement, compare collected files/count and passing behavior with the native runner, including runner-specific features.
- Inspect the full recursive removal closure. Remove only proven orphan declarations and their now-unused assertions/provisioning; do not introduce declarative cleanup for untracked leftovers. Live residual cleanup needs explicit approval. Compare Mason inventories before/after and retain unrelated packages; verify retained peer tools and headless editor startup.
- Distinguish direct size, total closure, unique closure, and reclaimable disk. Shared roots and old generations retain storage; broad garbage collection is separately authorized.
- Validate the producer before asserting absence; `! producer | grep ...` can turn a producer failure into a false pass.
- When correcting mistaken declarative ownership, revert only owned declaration/test changes and verify the intended native provider. Any stale-generation removal must preserve rollback/data under explicit cleanup authority.

## CI and platform checks

Inspect every affected workflow's exact command and earlier explicit provisioner; ShellCheck, cspell, and codespell are distinct. Add a focused dependency/order regression where warranted. Run in the CI environment and check mirrored Bash/PowerShell/macOS invariants. Hosted macOS self-tests must avoid GNU-only options even for Linux-deployed scripts.

Check runs by exact full SHA, allowing bounded registration delay. Inspect failed logs and whether tests ran. Rerun authorized transient infrastructure failures without speculative source changes, then inspect terminal results. Missing/pending/failed/unverifiable required checks block delivery gates. Activation wrappers must use the actual package owner (`cmp` is in diffutils); inspect combined output and require a clean rerun after hook errors.

## Portable JJ signing

1. Resolve `jj config path --user` and repository overrides. Edit the declarative source of managed links, not store targets. Inspect installed JJ documentation.
2. GPG with `signing.key` unset selects by `user.email`; it is not simply GPG's default key. Prefer native per-machine identity selection, preserving `signing.behavior` unless a change was authorized. Use local overrides only when necessary, never the first enumerated key.
3. Missing/unlocked-key failures remain visible; no unsigned fallback. Configuration does not provision keys or unlock them. Preserve another task's repository override and verify global values outside repositories.
4. Build/inspect, activate through the deployed role, then verify effective backend, key absence/override, behavior, and managed TOML. A Git signature is not proof of JJ signing; report config checks separately from actual signing.
5. If requirements change during delegated work, pause the writer, preserve the candidate, and rebuild/reverify corrected source before activation. Never deploy an earlier fingerprint-bearing generation merely because its old checks passed.
