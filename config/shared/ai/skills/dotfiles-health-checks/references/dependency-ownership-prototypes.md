# Dependency ownership prototypes

Use when considering replacing a framework, package manager, meta-layer, or bundled application with repository-owned configuration.

## Decision gate

Do not equate “we own it” with lower cost. Inventory actual usage first, then compare:

- dependency/closure and bootstrap reduction
- startup/runtime benefit
- added authored LOC and tests
- update and security ownership
- cross-platform burden
- user-visible parity and migration risk
- ability to validate on clean and upgrade environments

Prototype only when expected total cost improves. Rank and reject alternatives explicitly; “none” is valid.

## Bounded prototype

1. Use an isolated branch and worktree with one writer.
2. Start from current upstream; do not overlap another active worktree’s files without documenting conflicts.
3. Preserve user-visible behavior before optimizing benchmarks.
4. Add the smallest regression checks for trust boundaries, migration, and nontrivial logic.
5. Run repository-native focused and full checks.
6. Quantify additions, deletions, dependency reduction, runtime/storage change, and remaining parity gaps.
7. Require independent diff review; if review tooling is read-only, provide changed paths and full diff.
8. Commit locally only after validation. Do not merge, push, deploy, or mutate live state unless separately authorized.

## Removing a package manager used for very few packages

A package manager can be negative value when it exists for only one or two packages and requires bootstrap snapshots, hashes, updater logic, migration handling, manifests, and extensive tests.

Prefer native OS package management for ordinary binaries. For an artifact unavailable there, a direct installer is justified only if it remains materially smaller and preserves:

- pinned version and fail-closed checksum verification before extraction
- idempotent reinstall
- upgrades when old files are locked, usually through versioned destination names
- per-user registration and permissions
- existing application-visible identity
- non-destructive migration: do not remove the old package manager or its packages automatically

For per-user Windows fonts, validate archive contents, copy versioned `.ttf`/`.otf` files under `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, register them under `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`, and ensure packaged applications can read them. Test ACL failure as an error, not a warning.

## Host-scoped native-provider replacement

A binary available on the active host does not justify removing a shared Home Manager package from every Linux profile.

1. Trace the consumer through the real operation that needs the binary, including deferred builds and update hooks.
2. Evaluate every affected profile. A NixOS, generic Linux, or clean host may lack the native fallback seen on the current machine.
3. Prove the fallback is declaratively guaranteed, not residual/manual state. Inspect its native package owner, install reason, reverse dependencies, and bootstrap declaration.
4. In an isolated state directory, remove the managed package from `PATH` and run the real behavior. For editor-native compilation, isolate all XDG data/cache/state/config roots, compile a fresh parser or extension, and load the artifact.
5. If only one role owns the native provider, add one explicit false-by-default capability argument to that role. Keep the managed package in generic and other machine profiles; never use `isLinux` or an unrelated feature flag as the host-role proxy.
6. Build both sides and assert package exclusion and retention. Measure closure set differences rather than only the named package's closure.
   - Do not trust only the activation-package or generation closure: user-environment symlink targets can be omitted from that accounting.
   - Enumerate direct package roots, compute the union closure with and without the candidate, and use `nix why-depends` to identify another root that retains it.
   - Report direct NAR size, full closure, unique closure, and profile-path reduction separately. A removed declaration can have zero reclaimable closure when another package still depends on it.
7. Move ownership only when the native provider is already guaranteed by the accepted distro boundary or has an independent bootstrap need. Do not add a bootstrap dependency solely to remove its managed equivalent. Record the accepted guarantee in focused checks; current installation alone is not a clean-host guarantee.
8. Compare behavior semantically, not by byte-identical diagnostic output. Compile-time capabilities and default helper paths may differ; verify configured values plus real operations such as Git-over-SSH, SCP/SFTP, agent access, font matching/cache discovery, or fresh parser compilation as applicable.
9. Activate the exact deployed role. Require the command to resolve to the native owner, the managed binary to be absent from the active profile, the isolated behavior probe to pass again, and doctor/full checks to remain green.

This removes duplicate command ownership while preserving the capability and clean-host reproducibility. State when transitive Nix ownership remains rather than claiming closure savings.

## Repository-owned release versus native package

When a repository packages an official release artifact while the platform package set also provides the tool, do not assume the native declaration reduces total ownership:

1. Compare the repository's locked native-package version, the custom pin, and the current upstream immutable release. Benchmark the package that would actually replace the custom one, not a newer channel the repository does not use.
2. Build both packages. Record direct NAR size, full closure size, references, executable linkage, and supported platforms. A static official binary can be newer and materially smaller than a dynamically wrapped native package.
3. Run identical provider-free smoke checks from isolated writable homes: version, help, feature inventory, and local configuration/extension listing. Use alternating repeated startup probes only as a launcher-cost microbenchmark; never present them as interactive-agent performance.
4. Compare feature inventories when versions differ. Passing the same smoke commands does not establish feature parity if one package exposes fewer capabilities.
5. Trace shared pin consumers before counting removable code. If one release manifest also drives Windows or another non-native installer, replacing only the Unix package may retain most checksum/update machinery while introducing cross-platform version drift.
6. Report the exact replacement and net deletion estimate, but recommend replacement only when version and behavior are near-full parity and the total cross-platform ownership burden actually falls. Otherwise keep the custom package and name a measurable reconsideration trigger, such as the locked native package tracking upstream promptly.

## Acceptance gates

Static/Linux-hosted tests are insufficient for Windows provisioning. Before adoption, test both:

1. **Clean Windows VM:** native package installation, command resolution, registry entries, font ACLs, terminal family selection, text and glyph rendering.
2. **Existing-manager migration VM:** old manager and packages remain intact; replacement binary resolves correctly; versioned artifact installs and is used without destructive cleanup.

Keep these as explicit post-merge/manual gates if the code is merged before Windows validation. Never claim deployment validation from mocks alone.

## GUI package replacement warning

A package building and reporting the same version does not prove runtime parity. Exercise ordinary startup plus tray, settings, dialogs, media/screen sharing, and configuration preservation. Preserve wrapper environment and sandbox/fuse semantics. If a native package requires brittle repackaging and still crashes or bypasses wrapper behavior, revert and retain the working package rather than shipping nominal dependency reduction.
