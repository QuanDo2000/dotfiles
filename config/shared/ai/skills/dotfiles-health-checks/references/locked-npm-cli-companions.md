# Locked npm CLI companions

Use when an agent extension shells out to a CLI that should be owned by the same pinned npm closure and exposed through Nix/Home Manager.

## Minimal implementation

1. Read the extension’s executable discovery and invocation code. Record whether it expects a command on `PATH`, a JavaScript entrypoint, a global npm prefix, or a sibling `node_modules` path.
2. Add the CLI as an exact direct dependency of the existing private bundle and regenerate the lock with lifecycle scripts disabled.
3. Inspect all lock entries where `hasInstallScript == true`. Extend the updater’s exact package-name allowlist only for reviewed entries; keep production `npm ci`/Nix installation on `--ignore-scripts`.
4. Regenerate every coupled identity artifact: lockfile, release digest, extension paths in settings, and Nix `npmDepsHash`.
5. In the Nix package, expose the existing npm bin entry rather than writing a wrapper when a symlink is sufficient:
   ```nix
   mkdir -p "$out/bin"
   ln -s ../node_modules/.bin/tool "$out/bin/tool"
   ```
6. Add the bundle output to the narrowest Home Manager package set that needs the command. Do not add a native package-manager copy merely to replace Nix ownership.
7. For Windows, inspect the generated `.cmd`/`.ps1` shims. Some packages preserve a Unix `/bin/sh` shebang, making the local npm shim unusable in native Windows shells. Reuse an existing stable application bin that is already on `PATH` and create the smallest launcher:
   ```cmd
   @echo off
   node "C:\path\to\locked-release\node_modules\package\dist\cli.js" %*
   ```
   Validate the JavaScript target before writing the launcher. Keep launcher reconciliation after release validation but outside any “install only when missing” branch, so rerunning setup repairs a missing or stale launcher even when the immutable release is cached.

## Safe spikes

Many CLIs split mutable state across XDG roots. Setting only `XDG_CACHE_HOME` may still write collections or registries into the live user configuration. For isolated tests, set all four to temporary directories:

```sh
XDG_CONFIG_HOME="$tmp/config" \
XDG_CACHE_HOME="$tmp/cache" \
XDG_DATA_HOME="$tmp/data" \
XDG_STATE_HOME="$tmp/state" \
  tool ...
```

After any accidentally non-isolated spike, list the live registry and remove only the named test entries. Never clear the whole database.

## Verification ladder

- Lock assertions: exact direct dependency, integrity on every tarball, exact sorted install-script set.
- Package check: the exposed binary runs `--version` from `$out/bin`.
- Build: package and exact deployed Home Manager activation package from `path:.`.
- Activate through the repository-native role router. If a later privileged stage fails, separately verify that Home Manager activation completed.
- Runtime: resolve `command -v`/`readlink -f` into the intended Nix output. On Windows, require `Get-Command tool`, `tool --version`, and launcher content targeting the pinned immutable release; cross-platform PowerShell tests do not replace a native-Windows smoke test.
- Cached-release repair: delete only the generated launcher in an isolated fixture, rerun setup without reinstalling the release, and require the launcher to return.
- Application behavior: invoke the extension’s actual tool interface, not only the companion CLI. For search backends, exercise keyword and semantic modes without printing private result contents.
- Index health: after collection updates, inspect pending/orphaned counts; run scoped cleanup and embedding, then require both counts clear.
- Finish with focused tests, full repository checks, doctor, failed-unit checks, and final diff inspection.

## Pitfalls

- Cached fixed-output derivations can mask a reverted or stale `npmDepsHash`; the final dirty-worktree build is authoritative.
- Restoring a file from `HEAD` after formatting/conflict cleanup can silently restore the old dependency hash. Reapply and inspect all coupled pin fields together.
- Before running a formatter, check the baseline file with that formatter version. If baseline itself fails, preserve local style rather than creating an unrelated whole-file reformat.
- Package presence is not executable discovery. Windows npm-global lookup conventions can differ from local `node_modules/.bin`; verify each platform’s real lookup contract before claiming parity.
