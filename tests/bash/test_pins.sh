#!/usr/bin/env bash
# Cross-platform dependency pin updater tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_pin_updater_python_is_syntax_valid() {
  PYTHONPYCACHEPREFIX="$TEST_TMPDIR/pycache" python3 -m py_compile "$REPO_DIR/scripts/update_pins.py" 2>>"$ERROR_FILE"
}

test_pin_updater_keeps_security_checks() {
  local updater
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_contains "$(<"$REPO_DIR/scripts/pins.sh")" 'nix develop "path:$DOTFILES_DIR" -c'
  assert_contains "$(<"$REPO_DIR/flake.nix")" 'nodejs'
  assert_contains "$(<"$REPO_DIR/flake.nix")" 'neovim'
  assert_contains "$updater" 'repeated downloads differ'
  assert_contains "$updater" 'signed checksum mismatch'
  assert_contains "$updater" '"--certificate-identity"'
  assert_contains "$updater" 'member.issym() or member.islnk()'
  assert_contains "$updater" 'unsafe Pi extension lock entries'
  assert_contains "$updater" 'lock["fff.nvim"]["commit"] != fff["commit"]'
  assert_not_contains "$updater" 'shell=True'
}

test_pin_updater_sends_tokens_only_to_github() {
  PYTHONPATH="$REPO_DIR/scripts" python3 - <<'PY' 2>>"$ERROR_FILE"
import os
import update_pins
os.environ["GITHUB_TOKEN"] = "secret"
assert "Authorization" in update_pins.request("https://api.github.com/repos/example/example").headers
assert "Authorization" not in update_pins.request("https://registry.npmjs.org/example/latest").headers
assert "Authorization" not in update_pins.request("https://ankiweb.net/example").headers
PY
}

test_pin_wrapper_fails_closed_when_updater_fails() {
  DRY=false
  nix() { return 1; }

  local output status=0
  output="$(_update_webcord_release 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_contains "$output" "Failed to update WebCord release"
  unset -f nix
}

test_pin_updater_removes_excluded_skill_paths() {
  PYTHONPATH="$REPO_DIR/scripts" TEST_TMPDIR="$TEST_TMPDIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import os
from pathlib import Path
import update_pins

root = Path(os.environ["TEST_TMPDIR"]) / "skill"
(root / "nested").mkdir(parents=True)
(root / "README.md").touch()
(root / "nested" / "fixture.md").touch()
update_pins.remove_paths(root, ["README.md", "nested"])
assert not (root / "README.md").exists()
assert not (root / "nested").exists()

try:
    update_pins.remove_paths(root, ["../outside"])
except RuntimeError:
    pass
else:
    raise AssertionError("unsafe exclusion accepted")
PY
}
