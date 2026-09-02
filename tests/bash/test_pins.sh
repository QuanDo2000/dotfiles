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
  assert_contains "$updater" 'Mason registry GitHub digest mismatch'
  assert_contains "$updater" 'unexpected Mason registry archive entries'
  assert_contains "$updater" 'signed checksum mismatch'
  assert_contains "$updater" '"--certificate-identity"'
  assert_contains "$updater" 'member.issym() or member.islnk()'
  assert_contains "$updater" 'unsafe Pi extension lock entries'
  assert_contains "$updater" '"--no-audit"'
  assert_not_contains "$updater" 'fff.nvim'
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





test_mason_pin_extraction_requires_every_reviewed_tool() {
  PYTHONPATH="$REPO_DIR/scripts" python3 - <<'PY' 2>>"$ERROR_FILE"
import update_pins

versions = {
    "json-lsp": "4.10.0",
    "lua-language-server": "3.19.1",
    "markdownlint-cli2": "0.23.2",
    "marksman": "2026-02-08",
    "prettier": "3.9.6",
    "stylua": "v2.5.2",
    "taplo": "0.10.0",
    "yaml-language-server": "1.24.0",
}
registry = [{"name": name, "source": {"id": f"pkg:github/example/{name}@{version}"}} for name, version in versions.items()]
pins = update_pins.mason_pins_from_registry("registry-release", "a" * 64, registry)
assert pins["registryVersion"] == "registry-release"
assert pins["registrySha256"] == "a" * 64
assert pins["tools"] == versions
registry.pop()
try:
    update_pins.mason_pins_from_registry("registry-release", "a" * 64, registry)
except RuntimeError as error:
    assert "missing Mason package" in str(error)
else:
    raise AssertionError("missing Mason tool must fail")

import hashlib
import json
import zipfile
update_pins.fetch_json = lambda _: {
    "tag_name": "2026-08-23-wordy-july",
    "draft": False,
    "prerelease": False,
    "assets": [{"name": "registry.json.zip", "browser_download_url": "https://example/registry.zip"}],
}
def fake_download_twice(_, destination):
    with zipfile.ZipFile(destination, "w") as archive:
        archive.writestr("registry.json", json.dumps(registry + [{"name": "yaml-language-server", "source": {"id": "pkg:npm/yaml-language-server@1.24.0"}}]))
update_pins.download_twice = fake_download_twice
latest = update_pins.latest_mason_pins()
assert latest["registryVersion"] == "2026-08-23-wordy-july"
assert len(latest["registrySha256"]) == 64
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
lazy = Path(os.environ["TEST_TMPDIR"]) / "lazy.nvim"
lazy.mkdir()
commands = []

def fake_run(*args, cwd=None):
    return str(lazy)

def fake_subprocess_run(args, **kwargs):
    commands.append(args)
    if not any("require('config.sync').plugins(false)" in arg for arg in args):
        (Path(kwargs["env"]["XDG_CONFIG_HOME"]) / "nvim/lazy-lock.json").write_text("{}\n")
    return SimpleNamespace(returncode=0, stdout="", stderr="")

update_pins.run = fake_run
update_pins.subprocess.run = fake_subprocess_run
existing_pins = json.loads((repo / "config/shared/config/nvim/mason-tools.json").read_text())
update_pins.latest_mason_pins = lambda: existing_pins
update_pins.update_neovim(repo)
assert json.loads((repo / "config/shared/config/nvim/mason-tools.json").read_text()) == existing_pins
assert any("require('config.sync').plugins(false)" in arg for arg in commands[0])

update_pins.update_neovim = lambda _: (_ for _ in ()).throw(KeyError("plugin"))
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
current = json.loads(release_path.read_text())
assert "betterSqlite3" not in current
assert version_checks == [repo]

lock = json.loads(lock_path.read_text())
lock["packages"]["node_modules/pi-memory"]["version"] = "0.4.1"
lock_path.write_text(json.dumps(lock) + "\n")
current["releaseId"] = hashlib.sha256(lock_path.read_bytes()).hexdigest()
release_path.write_text(json.dumps(current) + "\n")
package["dependencies"]["pi-memory"] = "0.4.1"
(extensions / "package.json").write_text(json.dumps(package) + "\n")
update_pins.npm_latest = lambda name: package["dependencies"][name]

update_pins.update_pi_extensions(repo)
updated = json.loads(release_path.read_text())
assert version_checks == [repo, repo]
assert "betterSqlite3" not in updated
PY
}

test_skill_pin_update_skips_staging_when_commits_are_current() {
  PYTHONPATH="$REPO_DIR/scripts" TEST_TMPDIR="$TEST_TMPDIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import json
import os
from pathlib import Path
import update_pins

repo = Path(os.environ["TEST_TMPDIR"]) / "skills-repo"
skills = repo / "config/shared/ai/skills"
skills.mkdir(parents=True)
metadata = {
    "schemaVersion": 1,
    "example": {
        "repository": "https://github.com/example/example",
        "commit": "a" * 40,
        "path": "skills/example",
        "license": "example.LICENSE",
    },
}
(skills / "sources.json").write_text(json.dumps(metadata) + "\n")
update_pins.git_head = lambda _: "a" * 40
update_pins.shutil.copytree = lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("current skills should not be staged"))

update_pins.update_skills(repo)
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
