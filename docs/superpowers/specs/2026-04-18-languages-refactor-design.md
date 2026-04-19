# `scripts/languages.sh` deduplication refactor

## Background

`scripts/languages.sh` (774 lines) contains three GitHub-binary installers
(`install_zig`, `install_odin`, `install_gleam`) that share heavy structural
duplication, plus `install_jank` which is intentionally different (uses
system PM). The audit on 2026-04-18 flagged this as a real refactor
opportunity. Net reduction in `scripts/languages.sh` is expected to
be ~150 lines once helpers are added back (odin and gleam each shed
~70 lines; zig sheds ~10; ~50 lines of new helper code).

Existing test coverage: 85 tests in `tests/bash/test_languages.sh` cover
the helpers (target_triple, current_installed_version, latest_release,
sha256, etc.) and the dry-run paths. The actual download → verify →
extract → install flow is not exercised end-to-end, which makes a
naive refactor risky.

## Goal

Extract three small mechanical helpers used by all three installers, plus
one larger helper that absorbs the near-identical odin and gleam install
flows. Zig stays at the high level (its mirror retry + minisign verify
make it genuinely different) but uses the small helpers. Add integration
tests that exercise the new shared install path with real `tar` + real
`_sha256` + only `curl` mocked, so future refactors are safer.

## Out of scope

- Any changes to `install_jank` (system-PM-based; intentionally different).
- Any changes to zig's mirror retry loop or minisign verification.
- Splitting `languages.sh` into multiple files. The repo convention is
  one file per script.
- A real-network CI lane. Fixtures + curl mock are sufficient.

## New helpers

All three live near the top of `scripts/languages.sh`, alongside the
existing `_sha256` and `_shuffle_lines`. Function names start with `_`
to mark them as module-internal.

### `_assert_single_top_dir <extract_dir> <display_name>`

Replaces the bash-3.2 portable single-dir check duplicated in `install_zig`
(lines 256–263) and `install_odin` (lines 435–442).

Behavior:
- Counts top-level directories under `<extract_dir>` using a
  `while IFS= read -r ...; done < <(find ... -mindepth 1 -maxdepth 1 -type d)`
  loop (avoids `mapfile`/`-readarray` for bash 3.2 compatibility).
- If exactly 1 → prints the resolved path on stdout, returns 0.
- Otherwise → calls `fail "$display_name tarball extracted to unexpected
  layout ($count top-level dirs)"`.

### `_install_into_local <lc_name> <version> <bin_name> <extracted_path>`

Replaces the move + symlink + cleanup-old-versions block in all three
installers (zig 265–279, odin 444–458, gleam 626–642). Idempotent: safe
to call repeatedly.

Behavior:
1. `target_dir="$HOME/.local/${lc_name}-${version}"`
2. `rm -rf "$target_dir"; mv "$extracted_path" "$target_dir"` (fail on mv error)
3. `mkdir -p "$HOME/.local/bin"`
4. `ln -sfn "$target_dir/$bin_name" "$HOME/.local/bin/$bin_name"` (fail on link error)
5. Loop `for old in "$HOME"/.local/${lc_name}-*; do [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"; done`

No success log; the caller emits the language-specific success line.

### `_strip_sha256_prefix <digest>`

Replaces the inline 3-line dance in `install_odin` (399–405) and
`install_gleam` (584–591).

Behavior:
- `local stripped="${1#sha256:}"`
- If `stripped == $1` (prefix absent) → `fail "Unexpected digest format: $1"`.
- Else → `echo "$stripped"`.

## Merged installer: `_install_from_github_release`

Signature:

```bash
_install_from_github_release \
  <display_name> \   # "Odin"
  <lc_name> \        # "odin"
  <release_json> \   # body of GitHub releases/latest
  <tag> \            # already-extracted tag_name
  <asset> \          # "odin-linux-amd64-vN.N.N.tar.gz"
  <layout> \         # "single-dir" | "flat-binary"
  <bin_name>         # "odin"
```

Body:

1. Extract digest via jq from `.assets[] | select(.name == $a) | .digest`.
   Fail if empty.
2. `expected_sha=$(_strip_sha256_prefix "$digest")`.
3. Extract asset URL via jq `.browser_download_url`. Fail if empty.
4. `tmpdir=$(mktemp -d); trap "rm -rf '$tmpdir'" RETURN`.
5. `info "Downloading $asset_url"; curl -sfL "$asset_url" -o "$tmpdir/$asset"` — fail on error.
6. `got_sha=$(_sha256 "$tmpdir/$asset")`; fail if `!= expected_sha`.
7. `mkdir -p "$tmpdir/extract"; tar -xf "$tmpdir/$asset" -C "$tmpdir/extract"` — fail on error.
8. Layout-aware:
   - `single-dir`: `extracted=$(_assert_single_top_dir "$tmpdir/extract" "$display_name")`
   - `flat-binary`: assert `[[ -f "$tmpdir/extract/$bin_name" ]]`; otherwise fail.
     Then synthesize `mkdir -p "$tmpdir/wrapped"; mv "$tmpdir/extract/$bin_name" "$tmpdir/wrapped/$bin_name"; extracted="$tmpdir/wrapped"`.
   - anything else: fail "unknown layout".
9. `_install_into_local "$lc_name" "$tag" "$bin_name" "$extracted"`.
10. `success "Installed $display_name $tag"`.

## Refactored callers

### `install_odin` (was 363–461, ~99 lines → ~25 lines)

```bash
install_odin() {
  info "Installing Odin..."
  ensure_jq

  local triple
  triple="$(odin_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Odin for $triple"
    success "Finished installing Odin (dry run)"
    return 0
  fi

  local release_json
  release_json="$(odin_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  [[ -z "$tag" ]] && fail "Could not read tag_name from Odin releases/latest"

  local current
  current="$(odin_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Odin $tag"
    return 0
  fi

  local asset="odin-${triple}-${tag}.tar.gz"
  _install_from_github_release "Odin" "odin" "$release_json" "$tag" "$asset" "single-dir" "odin"
}
```

### `install_gleam` (was 547–645, ~98 lines → ~28 lines)

```bash
install_gleam() {
  info "Installing Gleam..."
  ensure_jq
  ensure_erlang
  ensure_rebar3

  local triple
  triple="$(gleam_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Gleam for $triple"
    success "Finished installing Gleam (dry run)"
    return 0
  fi

  local release_json
  release_json="$(gleam_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  [[ -z "$tag" ]] && fail "Could not read tag_name from Gleam releases/latest"

  local current
  current="$(gleam_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Gleam $tag"
    return 0
  fi

  local asset="gleam-${tag}-${triple}.tar.gz"
  _install_from_github_release "Gleam" "gleam" "$release_json" "$tag" "$asset" "flat-binary" "gleam"
}
```

### `install_zig` (was 161–282, ~121 lines → ~110 lines)

Inline sequence stays. Replace:
- The single-dir count loop (256–263) → `extracted=$(_assert_single_top_dir "$extract_dir" "Zig")`.
- The move + symlink + cleanup block (265–279) → `_install_into_local "zig" "$version" "zig" "$extracted"`.

Mirror retry loop and minisign verification are NOT touched.

## Tests

### Helper unit tests (~6)

Added to `tests/bash/test_languages.sh`:

- `test_assert_single_top_dir_returns_path_when_one_dir`
- `test_assert_single_top_dir_fails_when_zero_dirs`
- `test_assert_single_top_dir_fails_when_multiple_dirs`
- `test_install_into_local_creates_target_and_symlink`
- `test_install_into_local_cleans_old_versions`
- `test_strip_sha256_prefix_strips_known_format`
- `test_strip_sha256_prefix_fails_on_bare_hex`
- `test_strip_sha256_prefix_fails_on_sha512_prefix`

(8 actually; the count crept up. Still in the "~6" ballpark.)

### Integration tests for `_install_from_github_release` (~6)

Built around a test fixture: at test setup, create a real `.tar.gz`
containing either a single subdirectory (`single-dir` layout) or a
single binary at root (`flat-binary` layout). Compute its sha256.
Synthesize a release JSON with that sha256 in the digest field. Mock
`curl` so it copies the fixture file to the requested `-o` path.
Everything else (jq, tar, _sha256) runs for real.

- `test_install_from_github_release_single_dir_happy_path`
- `test_install_from_github_release_flat_binary_happy_path`
- `test_install_from_github_release_sha256_mismatch_fails`
- `test_install_from_github_release_missing_digest_fails`
- `test_install_from_github_release_single_dir_zero_dirs_fails`
- `test_install_from_github_release_flat_binary_missing_root_binary_fails`

## Acceptance criteria

- `bash tests/bash/runner.sh --no-docker` shows the existing 247 tests
  still passing plus the ~14 new ones (~261 total).
- `wc -l scripts/languages.sh` shrinks by roughly 150 lines (current 774
  → expected ~620, give or take).
- The existing dry-run tests for `install_zig`, `install_odin`,
  `install_gleam` continue to pass without modification.
- The existing `update_zig` / `update_odin` / `update_gleam` tests
  (which invoke their respective `install_*` in dry mode) continue to
  pass without modification.
- No real network calls, no real binary downloads during testing.

## Risk mitigation

5 commits, each independently testable:

1. Add `_assert_single_top_dir`, `_install_into_local`, `_strip_sha256_prefix`
   + their 8 unit tests. Pure addition; no callers.
2. Refactor `install_zig` to use `_assert_single_top_dir` + `_install_into_local`.
3. Add `_install_from_github_release` + its 6 integration tests. Pure
   addition; no callers.
4. Refactor `install_odin` to use `_install_from_github_release` (and the
   inline sha256-prefix dance to use `_strip_sha256_prefix`).
5. Refactor `install_gleam` to use `_install_from_github_release` (same).

After each commit, the full bash test suite must stay green.
