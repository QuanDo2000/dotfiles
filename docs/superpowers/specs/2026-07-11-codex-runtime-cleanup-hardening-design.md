# Codex Runtime Cleanup Hardening

## Scope

Improve the existing post-update Codex runtime cleanup without changing when
cleanup runs.

## Design

- Read `models_cache.json` with the already-managed `jq` package so formatted
  and multiline JSON is handled correctly.
- Preserve the current empty-result behavior when the file or
  `client_version` field is absent.
- Add regression coverage proving cleanup uses `CODEX_HOME` when set.
- Replace repeated Codex command mocks in the four update-cleanup tests with
  one local test helper while keeping each test's setup and assertions visible.

## Verification

- Demonstrate the multiline JSON test fails with the current `sed` parser.
- Run the focused package tests after implementation.
- Run the complete host Bash suite and `git diff --check` before completion.
