#!/usr/bin/env bash
# The reference patch must preserve the rest of the installed skill.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
setup() { init_test_env; }
teardown() { cleanup_test_env; }

test_hermes_security_patch_is_atomic_idempotent_and_preserves_assets() {
  local target="$HOME/.hermes/skills/autonomous-ai-agents/hermes-agent/references/security-privacy.md"
  local fix="$REPO_DIR/config/shared/ai/hermes/security-privacy.patch"
  local apply="$REPO_DIR/scripts/apply_hermes_skill_fixes.sh"
  mkdir -p "$(dirname "$target")"
  # Reconstruct the original hunk from the tracked upstream-compatible patch.
  python3 - "$fix" "$target" <<'PY'
import pathlib, sys
patch, target = map(pathlib.Path, sys.argv[1:])
lines = patch.read_text().splitlines(keepends=True)
target.write_text(''.join(line[1:] for line in lines if line.startswith((' ', '-')) and not line.startswith('---')))
PY
  printf 'keep every upstream asset\n' > "$(dirname "$target")/unrelated.md"
  cp "$target" "$TEST_TMPDIR/before"
  assert_exit_code 0 bash "$apply" "$fix"
  assert_contains "$(<"$target")" 'one-operation approval'
  assert_contains "$(<"$target")" 'non-interactive denial callback'
  assert_equals 'keep every upstream asset' "$(<"$(dirname "$target")/unrelated.md")"
  cp "$target" "$TEST_TMPDIR/after"
  assert_exit_code 0 bash "$apply" "$fix"
  cmp "$target" "$TEST_TMPDIR/after" || echo 'second application changed bytes' >> "$ERROR_FILE"
  printf 'upstream changed: require review\n' > "$target"
  cp "$target" "$TEST_TMPDIR/drift"
  assert_exit_code 1 bash "$apply" "$fix"
  cmp "$target" "$TEST_TMPDIR/drift" || echo 'source drift was overwritten' >> "$ERROR_FILE"
  rm "$target"
  ln -s "$TEST_TMPDIR/before" "$target"
  assert_exit_code 1 bash "$apply" "$fix"
  assert_symlink "$target" "$TEST_TMPDIR/before"
}
