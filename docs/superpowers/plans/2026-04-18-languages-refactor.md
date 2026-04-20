# `scripts/languages.sh` Deduplication Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract three small mechanical helpers used by all three GitHub-binary installers in `scripts/languages.sh`, plus one larger helper that absorbs the near-identical odin and gleam install flows. Add integration tests so future refactors are safer.

**Architecture:** All changes in `scripts/languages.sh` and `tests/bash/test_languages.sh`. Five-commit progression (helpers → zig refactor → integration helper → odin refactor → gleam refactor) keeps each change independently testable. Integration tests use a real `tar`-built fixture with only `curl` mocked.

**Tech Stack:** Bash, GNU/portable awk, jq, tar, sha256sum/shasum. Test runner: `tests/bash/runner.sh`. Mocking via the FAKE_BIN PATH-shadowing pattern.

**Related design spec:** `docs/superpowers/specs/2026-04-18-languages-refactor-design.md`

**Note on TDD discipline:** Tasks 1 and 3 add new helpers — write failing tests first. Tasks 2, 4, 5 are refactors of existing code that already has dry-run/short-circuit tests; the existing tests must continue to pass after each refactor (no new tests needed for those tasks).

---

## File map

- **Modify** `scripts/languages.sh`
  - Add three helpers near the top (after `_shuffle_lines`): `_assert_single_top_dir`, `_install_into_local`, `_strip_sha256_prefix`
  - Add `_install_from_github_release` after the per-language helper functions
  - Refactor `install_zig`, `install_odin`, `install_gleam` to call the new helpers
- **Modify** `tests/bash/test_languages.sh`
  - Extend `setup()` to add FAKE_BIN PATH-shadowing for integration tests (reuses pattern from `test_extras.sh`)
  - Add `mock_cmd` helper at the top
  - Add 8 unit tests for the small helpers
  - Add 6 integration tests for `_install_from_github_release` + supporting fixture builders

No new files.

---

## Task 1: Add small helpers + unit tests

**Files:**
- Modify: `scripts/languages.sh` (insert after line 29, the end of `_shuffle_lines`)
- Modify: `tests/bash/test_languages.sh` (extend setup, add mock_cmd, add 8 tests)

- [ ] **Step 1: Extend `setup()` and add `mock_cmd` in `tests/bash/test_languages.sh`**

Replace the current `setup()` and `teardown()` (lines 6-13) with:

```bash
setup() {
  init_test_env
  source_scripts utils.sh packages.sh languages.sh
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

# Helper: install a fake executable in FAKE_BIN that runs $body.
mock_cmd() {
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
}
```

- [ ] **Step 2: Run existing tests to verify no regression from setup change**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 85 passed, 0 failed, 85 total ===`

The existing 85 tests should still pass — adding FAKE_BIN to PATH does not affect any pure-helper test.

- [ ] **Step 3: Append the 8 unit tests to `tests/bash/test_languages.sh`**

Append to the bottom of `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# _assert_single_top_dir
# ---------------------------------------------------------------------------

test_assert_single_top_dir_returns_path_when_one_dir() {
  local extract_dir="$TEST_TMPDIR/single"
  mkdir -p "$extract_dir/inner"

  local result
  result=$(_assert_single_top_dir "$extract_dir" "TestPkg")
  assert_equals "$extract_dir/inner" "$result"
}

test_assert_single_top_dir_fails_when_zero_dirs() {
  local extract_dir="$TEST_TMPDIR/zero"
  mkdir -p "$extract_dir"
  # No subdirs.

  local output exit_code=0
  output=$(_assert_single_top_dir "$extract_dir" "TestPkg" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _assert_single_top_dir should fail with 0 dirs" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "TestPkg"
  assert_contains "$output" "0 top-level dirs"
}

test_assert_single_top_dir_fails_when_multiple_dirs() {
  local extract_dir="$TEST_TMPDIR/multi"
  mkdir -p "$extract_dir/a" "$extract_dir/b"

  local output exit_code=0
  output=$(_assert_single_top_dir "$extract_dir" "TestPkg" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _assert_single_top_dir should fail with 2 dirs" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "2 top-level dirs"
}

# ---------------------------------------------------------------------------
# _install_into_local
# ---------------------------------------------------------------------------

test_install_into_local_creates_target_and_symlink() {
  local extracted="$TEST_TMPDIR/extracted"
  mkdir -p "$extracted"
  echo "fake binary" > "$extracted/foo"
  chmod +x "$extracted/foo"

  _install_into_local "foo" "v1.0" "foo" "$extracted"

  assert_file_exists "$HOME/.local/foo-v1.0/foo"
  assert_symlink "$HOME/.local/bin/foo" "$HOME/.local/foo-v1.0/foo"
}

test_install_into_local_cleans_old_versions() {
  # Pre-create a prior version that should be removed by the cleanup loop.
  mkdir -p "$HOME/.local/foo-v0.9"
  echo "old" > "$HOME/.local/foo-v0.9/foo"

  local extracted="$TEST_TMPDIR/extracted"
  mkdir -p "$extracted"
  echo "new" > "$extracted/foo"

  _install_into_local "foo" "v1.0" "foo" "$extracted"

  assert_file_exists "$HOME/.local/foo-v1.0/foo"
  if [ -d "$HOME/.local/foo-v0.9" ]; then
    echo "  FAILED: _install_into_local should have removed old version foo-v0.9" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# _strip_sha256_prefix
# ---------------------------------------------------------------------------

test_strip_sha256_prefix_strips_known_format() {
  local result
  result=$(_strip_sha256_prefix "sha256:deadbeef")
  assert_equals "deadbeef" "$result"
}

test_strip_sha256_prefix_fails_on_bare_hex() {
  local output exit_code=0
  output=$(_strip_sha256_prefix "deadbeef" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _strip_sha256_prefix should fail on bare hex" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Unexpected digest format"
}

test_strip_sha256_prefix_fails_on_sha512_prefix() {
  local output exit_code=0
  output=$(_strip_sha256_prefix "sha512:abc" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _strip_sha256_prefix should fail on sha512: prefix" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Unexpected digest format"
}
```

- [ ] **Step 4: Run the new tests — they MUST fail (helpers not defined yet)**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: 8 new tests FAIL with "command not found" type errors. Original 85 still pass. Total 85 passed, 8 failed.

- [ ] **Step 5: Add the three helpers to `scripts/languages.sh`**

Open `scripts/languages.sh` and insert these helpers immediately after the closing `}` of `_shuffle_lines` (currently line 29):

```bash
# Assert that exactly one top-level directory exists under <extract_dir>.
# Prints the resolved path on stdout. Fails with $display_name in the message
# when the count is not 1. Uses a portable bash 3.2 loop (no mapfile/readarray).
_assert_single_top_dir() {
  local extract_dir="$1" display_name="$2"
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "$display_name tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi
  echo "$extracted"
}

# Move <extracted_path> to ~/.local/<lc_name>-<version>/, symlink the binary
# into ~/.local/bin/, and remove any prior ~/.local/<lc_name>-* siblings.
# Idempotent — safe to call repeatedly.
_install_into_local() {
  local lc_name="$1" version="$2" bin_name="$3" extracted_path="$4"
  local target_dir="$HOME/.local/${lc_name}-${version}"

  rm -rf "$target_dir"
  mv "$extracted_path" "$target_dir" || fail "Failed to move $lc_name into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/$bin_name" "$HOME/.local/bin/$bin_name" \
    || fail "Failed to create ~/.local/bin/$bin_name symlink"

  # Clean up old versions (any ~/.local/<lc_name>-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/"${lc_name}"-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done
}

# Strip the "sha256:" prefix from a GitHub release digest string.
# Fails loudly if the prefix is absent — the caller MUST NOT silently
# compare against a value of unknown algorithm.
_strip_sha256_prefix() {
  local digest="$1"
  local stripped="${digest#sha256:}"
  if [[ "$stripped" == "$digest" ]]; then
    fail "Unexpected digest format: $digest"
  fi
  echo "$stripped"
}
```

- [ ] **Step 6: Run the tests — all 93 should pass**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 93 passed, 0 failed, 93 total ===`

- [ ] **Step 7: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add small helpers for languages.sh: _assert_single_top_dir, _install_into_local, _strip_sha256_prefix"
```

---

## Task 2: Refactor `install_zig` to use the small helpers

**Files:**
- Modify: `scripts/languages.sh` (lines 256-279 in the pre-Task-1 numbering — locate by content, not line number)

- [ ] **Step 1: Replace the single-dir check + install block in `install_zig`**

Locate this block in `install_zig` (it spans the single-dir check at ~256-263 and the install-into-place block at ~265-279 in the original file; line numbers shift after Task 1 helpers are inserted):

```bash
  # Portable single-dir check (avoid mapfile/-readarray for bash 3.2 on macOS).
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "Tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi

  local target_dir="$HOME/.local/zig-$version"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Zig into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/zig" "$HOME/.local/bin/zig" \
    || fail "Failed to create ~/.local/bin/zig symlink"

  # Clean up old versions (any ~/.local/zig-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/zig-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done
```

Replace it with:

```bash
  local extracted
  extracted=$(_assert_single_top_dir "$extract_dir" "Zig")

  _install_into_local "zig" "$version" "zig" "$extracted"
```

- [ ] **Step 2: Run the full languages test suite — must still pass**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 93 passed, 0 failed, 93 total ===`

The existing zig tests (`test_install_zig_dry_run`, `test_install_zig_already_installed_short_circuits`, `test_update_zig_*`) all exercise the dry-run / already-installed paths which short-circuit before reaching the helper. They must continue passing.

- [ ] **Step 3: Commit**

```bash
git add scripts/languages.sh
git commit -m "Refactor install_zig to use _assert_single_top_dir + _install_into_local"
```

---

## Task 3: Add `_install_from_github_release` + integration tests

**Files:**
- Modify: `scripts/languages.sh` (add new function near the per-language helpers)
- Modify: `tests/bash/test_languages.sh` (add fixture builders + 6 integration tests)

- [ ] **Step 1: Append integration test fixtures and tests to `tests/bash/test_languages.sh`**

Append to the bottom of `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# _install_from_github_release — integration tests
# ---------------------------------------------------------------------------
# These tests exercise the real download → verify → extract → install flow
# with only `curl` mocked. The mock copies a real tarball fixture (built
# fresh per test) to the requested -o path.

# Build a tarball whose top-level layout is one directory containing $bin_name.
# Echoes the tarball path on stdout.
_build_single_dir_fixture() {
  local bin_name="$1" inner_dir="$2"
  local stage="$TEST_TMPDIR/stage_single_$$"
  mkdir -p "$stage/$inner_dir"
  echo "fake binary" > "$stage/$inner_dir/$bin_name"
  local tar_path="$TEST_TMPDIR/fixture_single_$$.tar.gz"
  tar -czf "$tar_path" -C "$stage" "$inner_dir"
  rm -rf "$stage"
  echo "$tar_path"
}

# Build a tarball whose root contains just the binary (no top-level dir).
_build_flat_binary_fixture() {
  local bin_name="$1"
  local stage="$TEST_TMPDIR/stage_flat_$$"
  mkdir -p "$stage"
  echo "fake binary" > "$stage/$bin_name"
  local tar_path="$TEST_TMPDIR/fixture_flat_$$.tar.gz"
  tar -czf "$tar_path" -C "$stage" "$bin_name"
  rm -rf "$stage"
  echo "$tar_path"
}

# Synthesize a release JSON containing exactly one asset with the given
# name, sha256, and download URL.
_make_release_json() {
  local tag="$1" asset="$2" sha="$3" url="$4"
  cat <<EOF
{
  "tag_name": "$tag",
  "assets": [
    {
      "name": "$asset",
      "digest": "sha256:$sha",
      "browser_download_url": "$url"
    }
  ]
}
EOF
}

# Install a curl mock that copies $INTEGRATION_FIXTURE to whatever -o path
# the caller provides. Other curl flags are ignored.
_mock_curl_copies_fixture() {
  mock_cmd curl '
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    shift
    out="$1"
  fi
  shift
done
[[ -z "$out" ]] && exit 1
cp "$INTEGRATION_FIXTURE" "$out"
'
}

test_install_from_github_release_single_dir_happy_path() {
  export INTEGRATION_FIXTURE
  INTEGRATION_FIXTURE=$(_build_single_dir_fixture "foo" "foo-1.0")
  local sha
  sha=$(_sha256 "$INTEGRATION_FIXTURE")
  local json
  json=$(_make_release_json "v1.0" "foo-1.0.tar.gz" "$sha" "https://example.com/foo.tar.gz")
  _mock_curl_copies_fixture

  _install_from_github_release "Foo" "foo" "$json" "v1.0" "foo-1.0.tar.gz" "single-dir" "foo"

  assert_file_exists "$HOME/.local/foo-v1.0/foo"
  assert_symlink "$HOME/.local/bin/foo" "$HOME/.local/foo-v1.0/foo"
}

test_install_from_github_release_flat_binary_happy_path() {
  export INTEGRATION_FIXTURE
  INTEGRATION_FIXTURE=$(_build_flat_binary_fixture "bar")
  local sha
  sha=$(_sha256 "$INTEGRATION_FIXTURE")
  local json
  json=$(_make_release_json "v2.0" "bar-2.0.tar.gz" "$sha" "https://example.com/bar.tar.gz")
  _mock_curl_copies_fixture

  _install_from_github_release "Bar" "bar" "$json" "v2.0" "bar-2.0.tar.gz" "flat-binary" "bar"

  assert_file_exists "$HOME/.local/bar-v2.0/bar"
  assert_symlink "$HOME/.local/bin/bar" "$HOME/.local/bar-v2.0/bar"
}

test_install_from_github_release_sha256_mismatch_fails() {
  export INTEGRATION_FIXTURE
  INTEGRATION_FIXTURE=$(_build_single_dir_fixture "foo" "foo-1.0")
  # Use a deliberately wrong sha to trigger mismatch.
  local json
  json=$(_make_release_json "v1.0" "foo-1.0.tar.gz" "0000000000000000000000000000000000000000000000000000000000000000" "https://example.com/foo.tar.gz")
  _mock_curl_copies_fixture

  local output exit_code=0
  output=$(_install_from_github_release "Foo" "foo" "$json" "v1.0" "foo-1.0.tar.gz" "single-dir" "foo" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: should have failed on sha256 mismatch" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "sha256 mismatch"
}

test_install_from_github_release_missing_digest_fails() {
  # Asset name in the JSON does not match what the helper looks for, so
  # jq returns empty for digest.
  local json='{"tag_name": "v1.0", "assets": [{"name": "wrong-name.tar.gz", "digest": "sha256:abc", "browser_download_url": "https://example.com/x.tar.gz"}]}'
  _mock_curl_copies_fixture

  local output exit_code=0
  output=$(_install_from_github_release "Foo" "foo" "$json" "v1.0" "expected-name.tar.gz" "single-dir" "foo" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: should have failed when digest missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Could not find digest for expected-name.tar.gz"
}

test_install_from_github_release_single_dir_zero_dirs_fails() {
  # Build a tarball that extracts to flat layout (no top-level dir),
  # then ask for single-dir layout — should fail.
  export INTEGRATION_FIXTURE
  INTEGRATION_FIXTURE=$(_build_flat_binary_fixture "foo")
  local sha
  sha=$(_sha256 "$INTEGRATION_FIXTURE")
  local json
  json=$(_make_release_json "v1.0" "foo.tar.gz" "$sha" "https://example.com/foo.tar.gz")
  _mock_curl_copies_fixture

  local output exit_code=0
  output=$(_install_from_github_release "Foo" "foo" "$json" "v1.0" "foo.tar.gz" "single-dir" "foo" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: should have failed when single-dir requested but no top-level dir" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "0 top-level dirs"
}

test_install_from_github_release_flat_binary_missing_root_binary_fails() {
  # Build a single-dir tarball, then ask for flat-binary layout — the
  # binary won't be at the root, so the layout check should fail.
  export INTEGRATION_FIXTURE
  INTEGRATION_FIXTURE=$(_build_single_dir_fixture "foo" "foo-1.0")
  local sha
  sha=$(_sha256 "$INTEGRATION_FIXTURE")
  local json
  json=$(_make_release_json "v1.0" "foo.tar.gz" "$sha" "https://example.com/foo.tar.gz")
  _mock_curl_copies_fixture

  local output exit_code=0
  output=$(_install_from_github_release "Foo" "foo" "$json" "v1.0" "foo.tar.gz" "flat-binary" "foo" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: should have failed when flat-binary requested but binary not at root" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Foo binary not found"
}
```

- [ ] **Step 2: Run the new tests — they MUST fail (helper not defined yet)**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: 6 new tests fail. Original 93 still pass. Total 93 passed, 6 failed.

- [ ] **Step 3: Add `_install_from_github_release` to `scripts/languages.sh`**

Insert this function in `scripts/languages.sh` immediately after the `_strip_sha256_prefix` helper added in Task 1 (i.e. before the existing `# Map (uname -s, uname -m) to Zig's tarball arch slug.` comment):

```bash
# Install a binary from a GitHub release tarball. Used by install_odin and
# install_gleam (zig has its own flow with mirror retry + minisign).
#
# Args (positional):
#   $1 display_name  e.g. "Odin"
#   $2 lc_name       e.g. "odin"
#   $3 release_json  body of GitHub releases/latest
#   $4 tag           already-extracted tag_name (e.g. "v1.2.3")
#   $5 asset         asset filename inside the release (e.g. "odin-...-v1.2.3.tar.gz")
#   $6 layout        "single-dir" (one top-level dir) or "flat-binary" (binary at root)
#   $7 bin_name      binary name to symlink (e.g. "odin")
_install_from_github_release() {
  local display_name="$1" lc_name="$2" release_json="$3" tag="$4"
  local asset="$5" layout="$6" bin_name="$7"

  local digest
  digest="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // empty')"
  if [[ -z "$digest" ]]; then
    fail "Could not find digest for $asset in $display_name releases/latest"
  fi
  local expected_sha
  expected_sha="$(_strip_sha256_prefix "$digest")"

  local asset_url
  asset_url="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .browser_download_url // empty')"
  if [[ -z "$asset_url" ]]; then
    fail "Could not find download URL for $asset in $display_name releases/latest"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tar_path="$tmpdir/$asset"
  info "Downloading $asset_url"
  curl -sfL "$asset_url" -o "$tar_path" \
    || fail "Failed to download $asset_url"

  local got_sha
  got_sha="$(_sha256 "$tar_path")"
  if [[ "$got_sha" != "$expected_sha" ]]; then
    fail "sha256 mismatch for $asset (expected $expected_sha, got $got_sha)"
  fi

  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tar_path" -C "$extract_dir" \
    || fail "Failed to extract $display_name tarball"

  local extracted
  case "$layout" in
    single-dir)
      extracted="$(_assert_single_top_dir "$extract_dir" "$display_name")"
      ;;
    flat-binary)
      if [[ ! -f "$extract_dir/$bin_name" ]]; then
        fail "$display_name binary not found at top level of tarball"
      fi
      # Wrap the bare binary in a directory so _install_into_local can mv it.
      mkdir -p "$tmpdir/wrapped"
      mv "$extract_dir/$bin_name" "$tmpdir/wrapped/$bin_name"
      extracted="$tmpdir/wrapped"
      ;;
    *)
      fail "_install_from_github_release: unknown layout: $layout"
      ;;
  esac

  _install_into_local "$lc_name" "$tag" "$bin_name" "$extracted"

  success "Installed $display_name $tag"
}
```

- [ ] **Step 4: Run the tests — all 99 should pass**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 99 passed, 0 failed, 99 total ===`

If any integration test fails, read the failure carefully — the fixture / mock infrastructure may need adjusting.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add _install_from_github_release helper with integration tests"
```

---

## Task 4: Refactor `install_odin` to use the new helper

**Files:**
- Modify: `scripts/languages.sh` (replace the body of `install_odin`)

- [ ] **Step 1: Replace `install_odin` body**

In `scripts/languages.sh`, locate `install_odin` (currently around lines 363–461 pre-task-1; line numbers have shifted). Replace the entire function with:

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
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Odin releases/latest"
  fi

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

- [ ] **Step 2: Run the full languages test suite — must still pass**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 99 passed, 0 failed, 99 total ===`

The existing odin tests (`test_install_languages_*` invoking odin in dry mode, `test_update_odin_*`) all exercise paths that short-circuit before reaching `_install_from_github_release`. They must continue passing.

- [ ] **Step 3: Commit**

```bash
git add scripts/languages.sh
git commit -m "Refactor install_odin to use _install_from_github_release"
```

---

## Task 5: Refactor `install_gleam` to use the new helper

**Files:**
- Modify: `scripts/languages.sh` (replace the body of `install_gleam`)

- [ ] **Step 1: Replace `install_gleam` body**

In `scripts/languages.sh`, locate `install_gleam` (originally lines 547–645 pre-task-1; line numbers have shifted). Replace the entire function with:

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
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Gleam releases/latest"
  fi

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

- [ ] **Step 2: Run the full languages test suite — must still pass**

Run: `bash tests/bash/runner.sh --no-docker test_languages.sh`
Expected: `=== Results: 99 passed, 0 failed, 99 total ===`

- [ ] **Step 3: Commit**

```bash
git add scripts/languages.sh
git commit -m "Refactor install_gleam to use _install_from_github_release"
```

---

## Task 6: Final regression check + line-count verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full bash suite**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: total tests = previous 247 + 14 new = 261. `=== Results: 261 passed, 0 failed, 261 total ===`

- [ ] **Step 2: Verify line-count reduction**

Run: `wc -l scripts/languages.sh`
Expected: ~620 lines (down from 774, give or take ~30). The exact number depends on formatting.

- [ ] **Step 3: Run Docker variant for sanity**

Run: `bash tests/bash/runner.sh test_languages.sh`
Expected: `=== Results: 99 passed, 0 failed, 99 total ===`

- [ ] **Step 4: No commit**

Verification only. If anything fails, return to the appropriate task.

---

## Self-Review Notes

**1. Spec coverage:**
- `_assert_single_top_dir` helper → Task 1 ✓
- `_install_into_local` helper → Task 1 ✓
- `_strip_sha256_prefix` helper → Task 1 ✓
- 8 unit tests for the small helpers → Task 1 ✓
- `_install_from_github_release` → Task 3 ✓
- 6 integration tests (single-dir happy, flat-binary happy, sha256 mismatch, missing digest, single-dir zero-dirs, flat-binary missing root binary) → Task 3 ✓
- Refactor install_zig to use the small helpers → Task 2 ✓
- Refactor install_odin to use `_install_from_github_release` → Task 4 ✓
- Refactor install_gleam to use `_install_from_github_release` → Task 5 ✓
- Acceptance criterion "existing 247 tests still pass + ~14 new" → Task 6 step 1 ✓
- Acceptance criterion "wc -l shrinks by ~150 lines" → Task 6 step 2 ✓
- Risk-mitigation: 5 commits, each independently testable → Tasks 1–5 each commit independently ✓

**2. Placeholder scan:** none. All code blocks are complete.

**3. Type/name consistency:**
- All three small helpers are referenced consistently across tasks: `_assert_single_top_dir`, `_install_into_local`, `_strip_sha256_prefix`.
- `_install_from_github_release` signature is consistent across Tasks 3, 4, 5: `(display_name, lc_name, release_json, tag, asset, layout, bin_name)`.
- Layout strings: `"single-dir"` and `"flat-binary"` are used identically in Task 3 (definition) and Tasks 4/5 (callers).
- `assert_file_exists` and `assert_symlink` exist in `tests/bash/runner.sh:83-101` (verified).
- `mock_cmd` defined in Task 1 step 1 is used in Task 3.
- `INTEGRATION_FIXTURE` env var is the pivot between fixture builders and the curl mock — both sides match.

**4. Note on line numbers:** The plan deliberately tells implementers to locate functions by name rather than relying on line numbers, because each task shifts the file. Tasks 2, 4, 5 explicitly say "locate by content".
