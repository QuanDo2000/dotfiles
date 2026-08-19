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
  assert_contains "$updater" '"--no-audit"'
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



test_neovim_pin_update_provisions_fresh_plugins_and_reports_internal_key_errors() {
  PYTHONPATH="$REPO_DIR/scripts" TEST_REPO_DIR="$REPO_DIR" TEST_TMPDIR="$TEST_TMPDIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import contextlib
import io
import json
import os
import shutil
import sys
from pathlib import Path
from types import SimpleNamespace
import update_pins

source = Path(os.environ["TEST_REPO_DIR"])
repo = Path(os.environ["TEST_TMPDIR"]) / "repo"
shutil.copytree(source / "config/shared/config/nvim", repo / "config/shared/config/nvim")
(repo / "packages").mkdir(parents=True)
shutil.copy2(source / "packages/fff-release.json", repo / "packages/fff-release.json")
backend = Path(os.environ["TEST_TMPDIR"]) / "backend.so"
lazy = Path(os.environ["TEST_TMPDIR"]) / "lazy.nvim"
backend.touch()
lazy.mkdir()
commands = []

def fake_run(*args, cwd=None):
    if args[:2] == ("nix", "build") and "#fff-nvim-backend" in args[2]:
        return str(backend)
    return str(lazy)

def fake_subprocess_run(args, **kwargs):
    commands.append(args)
    environment = kwargs["env"]
    assert environment["FFF_FRECENCY_DB"].startswith(environment["XDG_STATE_HOME"])
    assert environment["FFF_HISTORY_DB"].startswith(environment["XDG_STATE_HOME"])
    if not any("require('config.sync').plugins(false)" in arg for arg in args):
        (Path(kwargs["env"]["XDG_CONFIG_HOME"]) / "nvim/lazy-lock.json").write_text("{}\n")
    return SimpleNamespace(returncode=0, stdout="", stderr="")

update_pins.run = fake_run
update_pins.subprocess.run = fake_subprocess_run
update_pins.update_neovim(repo)
assert any("require('config.sync').plugins(false)" in arg for arg in commands[0])

update_pins.update_neovim = lambda _: (_ for _ in ()).throw(KeyError("fff.nvim"))
sys.argv = ["update_pins.py", "neovim", str(repo)]
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    status = update_pins.main()
assert status == 1
assert "pin update failed for neovim" in stderr.getvalue()
assert "Unknown pin target" not in stderr.getvalue()
PY
}

test_pi_extension_pin_update_prechecks_closure() {
  PYTHONPATH="$REPO_DIR/scripts" TEST_REPO_DIR="$REPO_DIR" TEST_TMPDIR="$TEST_TMPDIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import hashlib
import json
import os
import shutil
from pathlib import Path
import update_pins

source = Path(os.environ["TEST_REPO_DIR"])
repo = Path(os.environ["TEST_TMPDIR"]) / "pi-extensions"
extensions = repo / "config/shared/ai/pi/extensions"
extensions.mkdir(parents=True)
(repo / "packages").mkdir()
for relative in (
    "config/shared/ai/pi/extensions/package.json",
    "config/shared/ai/pi/extensions/package-lock.json",
    "packages/pi-extensions-release.json",
):
    destination = repo / relative
    shutil.copy2(source / relative, destination)

package = json.loads((extensions / "package.json").read_text())
release_path = repo / "packages/pi-extensions-release.json"
release = json.loads(release_path.read_text())
lock_path = extensions / "package-lock.json"
release["releaseId"] = hashlib.sha256(lock_path.read_bytes()).hexdigest()
release_path.write_text(json.dumps(release) + "\n")

update_pins.npm_latest = lambda name: package["dependencies"][name]
version_checks = []
def locked_node_version(path):
    version_checks.append(path)
    return release["node"]["version"]
update_pins.locked_node_version = locked_node_version
update_pins.locked_node = lambda _: (_ for _ in ()).throw(AssertionError("unchanged Node version should not build Node"))
update_pins.run = lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError(f"unexpected command: {args}"))
update_pins.verify_asset = lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("unexpected asset download"))

update_pins.update_pi_extensions(repo)
assert json.loads(release_path.read_text()) == release
assert version_checks == [repo]

release["betterSqlite3"]["assets"] = {}
release_path.write_text(json.dumps(release) + "\n")
downloads = []
def verify_asset(_, name, destination):
    downloads.append(name)
    destination.touch()
    return "a" * 64
update_pins.verify_asset = verify_asset
update_pins.fetch_json = lambda _: {}
update_pins.nix_hash = lambda _: "sha256-test"

update_pins.update_pi_extensions(repo)
updated = json.loads(release_path.read_text())
assert version_checks == [repo, repo]
assert len(downloads) == 4
assert set(updated["betterSqlite3"]["assets"]) == {
    "x86_64-linux", "aarch64-darwin", "windows-x64", "windows-arm64",
}
PY
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
