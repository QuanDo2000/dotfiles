# Odin language install — design spec

**Date:** 2026-04-18
**Status:** Approved (pending user spec review)
**Scope:** Add Odin as the second language under the existing `dotfile languages [LANG]` subcommand.

## Goal

Install the latest Odin release from GitHub into `~/.local/odin-<tag>/`, with `~/.local/bin/odin` symlinked to it. Mirror the Zig install pattern, simplified for Odin's single-source GitHub-only distribution model.

## Non-goals

- Windows support (`dotfile.ps1` is untouched; user installs Odin manually on Windows).
- Pinning to a specific Odin tag (always installs `releases/latest`).
- Replacing system / brew Odin (leaves foreign installs alone, same rule as Zig).
- Verifying the GitHub API response signature beyond TLS — Odin doesn't publish minisign signatures, so the SHA-256 from the same `releases/latest` JSON we use for the download URL is the strongest integrity check available.
- Adding a stable-channel split — Odin only publishes monthly dev releases (`dev-YYYY-MM`); there is no separate stable channel.

## CLI surface

No new commands. The existing `dotfile languages [LANG]` umbrella gains an `odin` arm:

```
dotfile languages           # install both zig and odin
dotfile languages odin      # install only odin
dotfile languages zig       # install only zig (unchanged)
dotfile update              # update both, only acting on installs we own
```

## Files added / changed

- **Modified:** `scripts/languages.sh` — append `odin_target_triple`, `odin_latest_release`, `odin_current_installed_version`, `install_odin`, `update_odin`. Extend `install_languages` and `update_languages`.
- **Modified:** `tests/bash/test_languages.sh` — add per-function tests for the new code, extend the umbrella tests.
- **Modified:** `CLAUDE.md` — add `languages` line to the `Key Commands` block (which previously omitted it).

## Install layout

```
~/.local/odin-<tag>/                # version-as-directory (e.g., odin-dev-2026-04/)
~/.local/odin-<tag>/odin            # the binary
~/.local/bin/odin                   # symlink → ~/.local/odin-<tag>/odin
```

The upstream tarball extracts to `odin-<arch>-<os>-<tag>/` (e.g. `odin-linux-amd64-dev-2026-04/`); the install step renames it to `odin-<tag>/` when moving into `~/.local/`. Same simplification rule as Zig — keeps `odin_current_installed_version`'s parsing stable across architectures.

`<tag>` is the full GitHub tag (e.g. `dev-2026-04`), preserved verbatim — no `dev-` stripping.

## Function inventory (additions to `scripts/languages.sh`)

### `odin_target_triple`

Map `(uname -s, uname -m)` to Odin's asset slug.

| `uname -s` | `uname -m` | Output |
|---|---|---|
| `Linux` | `x86_64` | `linux-amd64` |
| `Linux` | `aarch64` / `arm64` | `linux-arm64` |
| `Darwin` | `x86_64` | `macos-amd64` |
| `Darwin` | `arm64` / `aarch64` | `macos-arm64` |
| anything else | — | `fail` |

### `odin_latest_release`

```bash
odin_latest_release() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://api.github.com/repos/odin-lang/Odin/releases/latest")" \
      || fail "Failed to fetch Odin releases/latest"
  fi
  echo "$json"
}
```

Same optional-arg pattern as `zig_latest_stable` so `install_odin` can fetch once and pass through.

### `odin_current_installed_version`

Inspect `~/.local/bin/odin`. Return:
- empty if the symlink doesn't exist
- empty if it resolves outside `~/.local/odin-*/` (foreign)
- `<tag>` parsed from the parent directory name otherwise

Identical shape to `zig_current_installed_version`, just with the `odin-` prefix.

### `install_odin`

```text
1. info "Installing Odin..."
2. ensure_jq
3. triple = odin_target_triple
4. if DRY: log + return
5. release_json = odin_latest_release        # one fetch
6. tag    = jq '.tag_name'
7. asset  = "odin-${triple}-${tag}.tar.gz"
8. current = odin_current_installed_version
9. if current == tag: success "Already installed Odin $tag"; return
10. expected_sha = jq for that asset's .digest field, strip "sha256:" prefix
    if empty → fail "could not find sha256 for $asset in releases/latest"
11. asset_url = jq for that asset's .browser_download_url
    if empty → fail "could not find download URL for $asset"
12. mktemp -d; trap RETURN cleanup
13. curl -sfL "$asset_url" -o tar_path        # single source, no mirror loop
    on fail → fail "Failed to download $asset_url"
14. got_sha = _sha256 tar_path
    if got_sha != expected_sha → fail "sha256 mismatch for $asset"
15. tar -xzf tar_path -C extract_dir
16. portable single-dir check (read loop, same as install_zig)
17. mv extracted → ~/.local/odin-<tag>/, ln -sfn ~/.local/bin/odin
18. cleanup old ~/.local/odin-*/ that aren't <tag>
19. success "Installed Odin $tag"
```

Differences vs `install_zig`:
- No `ensure_minisign` call.
- No mirror loop, no `community-mirrors.txt`, no signature verification.
- SHA-256 comes from the metadata JSON we already fetched (one round-trip).
- Tarball is `.tar.gz` (use `tar -xzf` or rely on `tar -xf` auto-detect).

### `update_odin`

```bash
update_odin() {
  local current
  current="$(odin_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_odin
}
```

Exact analogue of `update_zig`.

## Umbrella changes

```bash
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig; install_odin ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    *)      fail "Unknown language: $target" ;;
  esac
}

update_languages() {
  update_zig
  update_odin
}
```

## Tests

### Additions to `tests/bash/test_languages.sh`

| Test | Purpose |
|---|---|
| `test_odin_target_triple_linux_x86_64` | `mock_uname Linux` + `mock_uname_m x86_64` → `linux-amd64` |
| `test_odin_target_triple_linux_aarch64` | → `linux-arm64` |
| `test_odin_target_triple_macos_x86_64` | → `macos-amd64` |
| `test_odin_target_triple_macos_aarch64` | → `macos-arm64` (test both `arm64` and `aarch64` if cheap) |
| `test_odin_target_triple_unsupported_arch_fails` | Linux + i686 → exits non-zero |
| `test_odin_latest_release_uses_passed_json` | Pass JSON arg → returns it verbatim, no `http_get_retry` call |
| `test_odin_latest_release_fetches_when_no_arg` | Stub `http_get_retry`, no arg → returns stub output |
| `test_odin_current_installed_version_none` | No symlink → empty |
| `test_odin_current_installed_version_ours_returns_tag` | Pre-create `~/.local/odin-dev-2026-04/odin` + symlink → `dev-2026-04` |
| `test_odin_current_installed_version_foreign_returns_empty` | Symlink to `/usr/bin/odin` → empty |
| `test_install_odin_dry_run` | `DRY=true` → log lines, no network attempted |
| `test_install_odin_already_installed_short_circuits` | Pre-create symlink at the tag the stubbed JSON reports → "Already installed Odin <tag>" |
| `test_update_odin_no_op_when_not_installed` | No symlink → silent |
| `test_update_odin_skips_foreign_install` | Foreign symlink → silent |
| `test_update_odin_dry_run_when_ours` | Pre-existing ours + DRY=true → "Installing Odin" log |
| `test_install_languages_odin_only_arg` | `install_languages odin` runs install_odin |
| `test_install_languages_all_runs_both` | Replace existing `test_install_languages_all_arg` to assert BOTH "Installing Zig" AND "Installing Odin" appear |

The download / SHA-256 / extract loop is unit-untestable — covered by manual smoke test.

### Manual smoke test

Mirror Plan Task 13 from the Zig branch, scoped to Odin and the running host (Arch x86_64):

1. Fresh install: `rm -rf ~/.local/odin-* ~/.local/bin/odin && bash ./dotfile languages odin && ~/.local/bin/odin version` — version output should match the latest GitHub tag (verify by visiting https://github.com/odin-lang/Odin/releases/latest).
2. Re-install: re-run, expect "Already installed Odin <tag>" and no new files.
3. `update_odin` (real, not dry) — expect short-circuit when current.
4. Foreign-install no-op: replace symlink with one pointing at `/tmp/fake-odin`, run `update_odin`, expect zero output. Restore.
5. SHA-256 mismatch: temporarily edit the downloaded tarball mid-flight (or seed a wrong expected_sha via a stub-style debug run), confirm `fail "sha256 mismatch …"` fires before extraction. Optional — code review covers this path.
6. Mac smoke test deferred (no Mac available).

## Error handling

- `set -eo pipefail` already at top of `languages.sh`.
- `fail` for unrecoverable errors (download failure, SHA mismatch, missing asset in JSON).
- `trap … RETURN` for tmpdir cleanup, matching `install_zig` (best-effort — `fail`/`exit` short-circuits don't fire RETURN, same caveat).

## CLAUDE.md update

Add a single line to the `Key Commands` block:

```
dotfile languages [LANG]    # Install language toolchains (zig, odin)
```

Don't backfill the other missing commands (`obsidian`, `update`, etc.) — that's pre-existing drift, out of scope here.

## Open questions

None. All decisions resolved during brainstorming.

## Out of scope (future work)

- A `dotfile languages odin <tag>` form to pin to a specific release.
- Verifying GitHub release attestations via `gh attestation verify` (would require `gh` CLI as a hard dependency).
- A `dotfile uninstall <language>` complement.
