# Codex Runtime Cleanup Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex cache-version detection JSON-safe, verify custom `CODEX_HOME` cleanup, and remove repeated test mocks.

**Architecture:** Keep production behavior in the existing `scripts/packages.sh` helpers. Use the already-installed `jq` command for JSON parsing and one test-only helper to configure common Codex/update mocks while individual tests retain their assertions.

**Tech Stack:** Bash, jq, existing Bash test runner

## Global Constraints

- Do not change when post-update cleanup runs.
- Preserve an empty cache-version result when the cache or field is absent.
- Add no dependencies; `jq` is already managed and available in tests.
- Keep each cleanup test's behavior-specific assertions visible.

---

### Task 1: JSON-safe cache-version parsing

**Files:**
- Modify: `scripts/packages.sh:200-206`
- Test: `tests/bash/test_packages.sh`

**Interfaces:**
- Consumes: `_codex_model_cache_version` reads `${CODEX_HOME:-$HOME/.codex}/models_cache.json`.
- Produces: `_codex_model_cache_version` prints `.client_version` or an empty string.

- [ ] **Step 1: Write the failing multiline JSON test**

```bash
test_codex_model_cache_version_reads_multiline_json() {
  mkdir -p "$HOME/.codex"
  printf '{\n  "client_version": "0.144.1"\n}\n' > "$HOME/.codex/models_cache.json"

  assert_equals "0.144.1" "$(_codex_model_cache_version)"
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: `test_codex_model_cache_version_reads_multiline_json` fails because the current line-based `sed` expression returns empty output.

- [ ] **Step 3: Replace line parsing with jq**

```bash
jq -r '.client_version // empty' "$cache_file" 2>/dev/null || true
```

- [ ] **Step 4: Run focused tests**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all package tests pass.

### Task 2: Custom CODEX_HOME cleanup coverage

**Files:**
- Test: `tests/bash/test_packages.sh`

**Interfaces:**
- Consumes: `_cleanup_stale_codex_runtime` and the exported `CODEX_HOME` override.
- Produces: regression coverage for cache and socket paths below `CODEX_HOME`.

- [ ] **Step 1: Add the custom-home regression test**

```bash
test_cleanup_stale_codex_runtime_uses_codex_home() {
  CODEX_HOME="$TEST_TMPDIR/codex-home"
  local calls="$TEST_TMPDIR/calls.log"
  codex() { :; }
  rm() { printf 'rm %s\n' "$*" > "$calls"; }

  _cleanup_stale_codex_runtime

  assert_contains "$(<"$calls")" "$CODEX_HOME/models_cache.json"
  assert_contains "$(<"$calls")" "$CODEX_HOME/app-server-control/app-server-control.sock"
  unset -f codex rm
  unset CODEX_HOME
}
```

- [ ] **Step 2: Run focused tests**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all package tests pass; production already supports this behavior.

### Task 3: Deduplicate update-cleanup test mocks

**Files:**
- Modify: `tests/bash/test_packages.sh:538-693`

**Interfaces:**
- Produces: `_mock_codex_update_runtime <calls-file> <version>` test helper and
  `MOCK_CODEX_VERSION` state that a test may update after Home Manager runs.
- Consumes: caller-defined `home-manager` when a test needs to mutate the version.

- [ ] **Step 1: Extract the common command, codex, and rm mocks**

```bash
_mock_codex_update_runtime() {
  MOCK_CODEX_CALLS="$1"
  MOCK_CODEX_VERSION="$2"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in codex|nix|home-manager) return 0 ;; esac
    fi
    builtin command "$@"
  }
  codex() {
    case "$*" in
      "--version") printf '%s\n' "$MOCK_CODEX_VERSION" ;;
      "app-server daemon stop") printf 'codex-stop\n' >> "$MOCK_CODEX_CALLS" ;;
    esac
  }
  rm() { printf 'rm %s\n' "$*" >> "$MOCK_CODEX_CALLS"; }
}
```

- [ ] **Step 2: Update the four cleanup tests to call the helper**

Each test calls `_mock_codex_update_runtime "$calls" "codex-cli 0.144.1"` and
retains its existing `home-manager` behavior and assertions. The version-change
test sets `MOCK_CODEX_VERSION="codex-cli 0.144.1"` inside `home-manager`.

- [ ] **Step 3: Run focused tests**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all package tests pass with fewer repeated mock definitions.

### Task 4: Final verification

**Files:**
- Verify: `scripts/packages.sh`
- Verify: `tests/bash/test_packages.sh`

- [ ] **Step 1: Run complete Bash tests**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: 0 failed tests.

- [ ] **Step 2: Check patch whitespace**

Run: `git diff --check`
Expected: no output and exit code 0.

- [ ] **Step 3: Review scope**

Run: `git diff -- scripts/packages.sh tests/bash/test_packages.sh`
Expected: only jq parsing, the two regression tests, and test mock deduplication.
