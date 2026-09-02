#!/usr/bin/env python3
"""Refresh repository-held dependency pins. Called only by `dotfile update`."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

USER_AGENT = "dotfiles-pin-updater/1"
MASON_TOOLS = (
    "json-lsp",
    "lua-language-server",
    "markdownlint-cli2",
    "marksman",
    "prettier",
    "stylua",
    "taplo",
    "yaml-language-server",
)


def die(message: str) -> None:
    raise RuntimeError(message)


def run(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, check=True)
    return result.stdout.strip()


def request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    host = (urllib.parse.urlparse(url).hostname or "").lower()
    if token and (host == "github.com" or host.endswith(".github.com") or host.endswith(".githubusercontent.com")):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(request(url), timeout=60) as response:
        return json.load(response)


def download(url: str, destination: Path) -> None:
    with urllib.request.urlopen(request(url), timeout=120) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def download_twice(url: str, destination: Path) -> None:
    second = destination.with_name(destination.name + ".second")
    try:
        download(url, destination)
        download(url, second)
        if sha256(destination) != sha256(second):
            die(f"repeated downloads differ: {url}")
    finally:
        second.unlink(missing_ok=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def nix_hash(path: Path) -> str:
    return run("nix", "hash", "file", "--type", "sha256", str(path))


def atomic_text(path: Path, text: str) -> None:
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def atomic_json(path: Path, value: object) -> None:
    atomic_text(path, json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        die(f"expected one occurrence in {path}: {old}")
    atomic_text(path, text.replace(old, new))


def replace_all(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        die(f"missing value in {path}: {old}")
    atomic_text(path, text.replace(old, new))


def replace_pattern(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        die(f"pattern did not match once in {path}: {pattern}")
    atomic_text(path, updated)


def github_release(repository: str) -> dict:
    release = fetch_json(f"https://api.github.com/repos/{repository}/releases/latest")
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        die(f"unexpected latest release for {repository}: {tag}")
    return release


def github_asset(release: dict, name: str) -> dict:
    matches = [asset for asset in release.get("assets", []) if asset.get("name") == name]
    if len(matches) != 1:
        die(f"release asset missing or duplicated: {name}")
    return matches[0]


def verify_asset(release: dict, name: str, destination: Path, checksum_file: bool = False) -> str:
    asset = github_asset(release, name)
    download(asset["browser_download_url"], destination)
    actual = sha256(destination)
    digest = asset.get("digest")
    if digest and digest != f"sha256:{actual}":
        die(f"GitHub digest mismatch for {name}")
    if checksum_file:
        checksum_asset = github_asset(release, name + ".sha256")
        checksum_path = destination.with_name(destination.name + ".sha256")
        download(checksum_asset["browser_download_url"], checksum_path)
        expected = checksum_path.read_text(encoding="utf-8").split()[0].lower()
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or expected != actual:
            die(f"upstream checksum mismatch for {name}")
    return actual


def locked_node(repo: Path) -> tuple[str, str]:
    expression = (
        f'let f = builtins.getFlake "path:{repo}"; '
        "in (import f.inputs.nixpkgs { system = builtins.currentSystem; }).nodejs"
    )
    output = run("nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr", expression)
    node = Path(output.splitlines()[-1]) / "bin/node"
    version = run(str(node), "-p", "process.version.slice(1)")
    abi = run(str(node), "-p", "process.versions.modules")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not abi.isdigit():
        die("failed to resolve locked Node version/ABI")
    return version, abi


def npm_latest(package: str) -> str:
    encoded = urllib.parse.quote(package, safe="@/")
    version = fetch_json(f"https://registry.npmjs.org/{encoded}/latest").get("version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        die(f"unexpected npm version for {package}: {version}")
    return version


def locked_node_version(repo: Path) -> str:
    expression = (
        f'let f = builtins.getFlake "path:{repo}"; '
        "in (import f.inputs.nixpkgs { system = builtins.currentSystem; }).nodejs.version"
    )
    version = run("nix", "eval", "--raw", "--impure", "--expr", expression)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        die("failed to resolve locked Node version")
    return version


def update_pi_extensions(repo: Path) -> None:
    package_path = repo / "config/shared/ai/pi/extensions/package.json"
    lock_path = package_path.with_name("package-lock.json")
    release_path = repo / "packages/pi-extensions-release.json"
    package = json.loads(package_path.read_text(encoding="utf-8"))
    latest_dependencies = {name: npm_latest(name) for name in package["dependencies"]}
    if package["dependencies"] != latest_dependencies:
        package["dependencies"] = latest_dependencies
        atomic_json(package_path, package)
        run(
            "npm", "install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--legacy-peer-deps", "--omit=dev",
            cwd=package_path.parent,
        )

    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    invalid = [
        name for name, value in lock["packages"].items()
        if name and not value.get("link") and (
            not str(value.get("resolved", "")).startswith("https://")
            or not str(value.get("integrity", "")).startswith("sha512-")
        )
    ]
    allowed_install_scripts = {
        "node_modules/node-llama-cpp",
        "node_modules/pi-memory",
        "node_modules/tree-sitter-go",
        "node_modules/tree-sitter-javascript",
        "node_modules/tree-sitter-python",
        "node_modules/tree-sitter-rust",
        "node_modules/tree-sitter-typescript",
    }
    install_scripts = [name for name, value in lock["packages"].items() if value.get("hasInstallScript")]
    unexpected_scripts = [name for name in install_scripts if name not in allowed_install_scripts]
    if invalid or unexpected_scripts:
        die(f"unsafe Pi extension lock entries: invalid={invalid}, scripts={unexpected_scripts}")

    release_id = sha256(lock_path)

    old = json.loads(release_path.read_text(encoding="utf-8"))
    old_node = old.get("node", {})
    node_version = locked_node_version(repo)
    if old_node.get("version") == node_version and str(old_node.get("abi", "")).isdigit():
        abi = str(old_node["abi"])
    else:
        resolved_version, abi = locked_node(repo)
        if resolved_version != node_version:
            die("locked Node version changed during resolution")
        node_version = resolved_version
    updated = {
        "releaseId": release_id,
        "node": {"version": node_version, "abi": abi},
    }
    if old == updated:
        print(f"Pi extensions already current (Node {node_version}, ABI {abi})")
        return
    atomic_json(release_path, updated)

    if old["releaseId"] != release_id:
        prefetch = run("nix", "run", f"path:{repo}#prefetch-npm-deps", "--", str(lock_path))
        matches = re.findall(r"sha256-[A-Za-z0-9+/=]+", prefetch)
        if not matches:
            die("prefetch-npm-deps returned no hash")
        package_nix = repo / "packages/pi-extensions.nix"
        replace_pattern(package_nix, r'npmDepsHash = "sha256-[^"]+";', f'npmDepsHash = "{matches[-1]}";')
        settings = repo / "config/shared/ai/pi/settings.json"
        replace_all(settings, old["releaseId"], release_id)
    if old["node"]["version"] != node_version:
        workflow = repo / ".github/workflows/test.yml"
        replace_once(workflow, f'node-version: {old["node"]["version"]}', f"node-version: {node_version}")
    print(f"updated Pi extensions to {release_id[:12]} (Node {node_version}, ABI {abi})")


def update_webcord(repo: Path) -> None:
    package = repo / "packages/webcord-release.nix"
    text = package.read_text(encoding="utf-8")
    current_match = re.search(r'version = "([0-9]+\.[0-9]+\.[0-9]+)";', text)
    if not current_match:
        die("failed to parse WebCord version")
    current = current_match.group(1)
    release = github_release("SpacingBat3/WebCord")
    version = release["tag_name"].removeprefix("v")
    if current == version:
        print(f"WebCord {version} already current")
        return
    name = f"WebCord-{version}-x64.AppImage"
    with tempfile.TemporaryDirectory(prefix="dotfiles-webcord-") as temporary:
        path = Path(temporary) / name
        download_twice(github_asset(release, name)["browser_download_url"], path)
        digest = github_asset(release, name).get("digest")
        if digest and digest != f"sha256:{sha256(path)}":
            die("WebCord GitHub digest mismatch")
        sri = nix_hash(path)
    replace_once(package, f'version = "{current}";', f'version = "{version}";')
    replace_pattern(package, r'hash = "sha256-[^"]+";', f'hash = "{sri}";')
    print(f"updated WebCord to {version}")


def update_anki_zoom(repo: Path) -> None:
    url = "https://ankiweb.net/shared/download/1923741581?v=2.1&p=2509004"
    home = repo / "config/home.nix"
    with tempfile.TemporaryDirectory(prefix="dotfiles-anki-") as temporary:
        archive = Path(temporary) / "anki-zoom24.zip"
        download_twice(url, archive)
        with zipfile.ZipFile(archive) as source:
            if any(info.is_dir() is False and (info.filename.startswith("/") or ".." in Path(info.filename).parts) for info in source.infolist()):
                die("unsafe Anki add-on archive")
            newest = max(info.date_time for info in source.infolist())
        version = f"{newest[0]:04d}-{newest[1]:02d}-{newest[2]:02d}"
        base32 = run("nix-prefetch-url", "--unpack", "--name", "anki-zoom24.zip", archive.as_uri())
        sri = run("nix", "hash", "to-sri", "--type", "sha256", base32)
    text = home.read_text(encoding="utf-8")
    current_version = re.search(r'pname = "zoom24";\n\s+version = "([^"]+)";', text)
    current_hash = re.search(r'pname = "zoom24";.*?hash = "([^"]+)";', text, re.DOTALL)
    if not current_version or not current_hash:
        die("failed to parse Anki Zoom pin")
    if current_version.group(1) == version and current_hash.group(1) == sri:
        print(f"Anki Zoom {version} already current")
        return
    replace_once(home, f'version = "{current_version.group(1)}";', f'version = "{version}";')
    replace_once(home, f'hash = "{current_hash.group(1)}";', f'hash = "{sri}";')
    print(f"updated Anki Zoom to {version}")


def git_head(repository: str) -> str:
    output = run("git", "ls-remote", f"https://github.com/{repository}.git", "HEAD")
    commit = output.split()[0] if output else ""
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        die(f"failed to resolve HEAD for {repository}")
    return commit


def update_firacode(repo: Path) -> None:
    script = repo / "dotfile.ps1"
    text = script.read_text(encoding="utf-8")
    version_match = re.search(r"\$script:FiraCodeNerdFontVersion = '([^']+)'", text)
    url_match = re.search(r"\$script:FiraCodeNerdFontUrl = '([^']+)'", text)
    hash_match = re.search(r"\$script:FiraCodeNerdFontSha256 = '([0-9a-f]{64})'", text)
    if not version_match or not url_match or not hash_match:
        die("failed to parse FiraCode Nerd Font pins")
    release = github_release("ryanoasis/nerd-fonts")
    version = release["tag_name"].removeprefix("v")
    if version_match.group(1) == version:
        print(f"FiraCode Nerd Font {version} already current")
        return
    name = "FiraCode.zip"
    url = github_asset(release, name)["browser_download_url"]
    with tempfile.TemporaryDirectory(prefix="dotfiles-firacode-") as temporary:
        path = Path(temporary) / name
        download_twice(url, path)
        digest = github_asset(release, name).get("digest")
        if digest and digest != f"sha256:{sha256(path)}":
            die("FiraCode GitHub digest mismatch")
        archive_hash = sha256(path)
    text = text.replace(version_match.group(0), f"$script:FiraCodeNerdFontVersion = '{version}'", 1)
    text = text.replace(url_match.group(0), f"$script:FiraCodeNerdFontUrl = '{url}'", 1)
    text = text.replace(hash_match.group(0), f"$script:FiraCodeNerdFontSha256 = '{archive_hash}'", 1)
    atomic_text(script, text)
    print(f"updated FiraCode Nerd Font to {version}")


def safe_extract_tar(archive: Path, destination: Path) -> Path:
    destination.mkdir(parents=True)
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        safe_members = []
        for member in members:
            parts = Path(member.name).parts
            if member.name.startswith("/") or ".." in parts:
                die(f"unsafe archive member: {member.name}")
            # Never materialize links from upstream. Selected skills that depend on
            # one then fail their required SKILL.md/tree checks below.
            if member.issym() or member.islnk():
                continue
            safe_members.append(member)
        source.extractall(destination, members=safe_members, filter="data")
    roots = [path for path in destination.iterdir() if path.is_dir()]
    if len(roots) != 1:
        die("source archive must contain one root directory")
    return roots[0]


def remove_paths(root: Path, paths: list[str]) -> None:
    for relative in paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            die(f"unsafe excluded skill path: {relative}")
        target = root / path
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.is_dir():
            shutil.rmtree(target)


def update_skills(repo: Path) -> None:
    skills = repo / "config/shared/ai/skills"
    metadata_path = skills / "sources.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    updates = []
    for name, source in metadata.items():
        if name == "schemaVersion":
            continue
        repository = source["repository"].removeprefix("https://github.com/").removesuffix(".git")
        commit = git_head(repository)
        if commit != source["commit"]:
            updates.append((name, source, repository, commit))
    if not updates:
        print("vendored agent skills already current")
        return

    staged_parent = Path(tempfile.mkdtemp(prefix="dotfiles-skills-", dir=skills.parent))
    staged = staged_parent / "skills"
    shutil.copytree(skills, staged)
    changed = []
    try:
        for name, source, repository, commit in updates:
            archive_url = f"https://github.com/{repository}/archive/{commit}.tar.gz"
            with tempfile.TemporaryDirectory(prefix=f"dotfiles-skill-{name}-") as temporary:
                root = Path(temporary)
                archive = root / "source.tar.gz"
                download_twice(archive_url, archive)
                extracted = safe_extract_tar(archive, root / "extracted")
                paths = source.get("paths") or [source["path"]]
                for relative in paths:
                    source_path = extracted / relative
                    if not source_path.is_dir() or not (source_path / "SKILL.md").is_file():
                        die(f"missing selected skill path: {relative}")
                    destination = staged / Path(relative).name
                    shutil.rmtree(destination, ignore_errors=True)
                    shutil.copytree(source_path, destination)
                remove_paths(staged, source.get("excludedPaths", []))
                license_source = next((extracted / candidate for candidate in ("LICENSE", "LICENSE.md") if (extracted / candidate).is_file()), None)
                if license_source is None:
                    die(f"missing upstream license for {name}")
                shutil.copy2(license_source, staged / source["license"])
                source["commit"] = commit
                source["observedArchiveSha256"] = sha256(archive)
                changed.append(name)
        atomic_json(staged / "sources.json", metadata)
        backup = skills.with_name(f"skills.backup.{os.getpid()}")
        os.replace(skills, backup)
        try:
            os.replace(staged, skills)
        except Exception:
            os.replace(backup, skills)
            raise
        shutil.rmtree(backup)
        print("updated vendored skills: " + ", ".join(changed))
    finally:
        shutil.rmtree(staged_parent, ignore_errors=True)


def mason_pins_from_registry(registry_version: str, registry_sha256: str, registry: list[dict]) -> dict:
    packages = {package.get("name"): package for package in registry}
    tools = {}
    for name in MASON_TOOLS:
        package = packages.get(name)
        if package is None:
            die(f"missing Mason package: {name}")
        source_id = str(package.get("source", {}).get("id", ""))
        if "@" not in source_id:
            die(f"Mason package has no pinned source version: {name}")
        version = source_id.rsplit("@", 1)[1].split("?", 1)[0]
        if not version or re.search(r"\s", version):
            die(f"invalid Mason package version for {name}: {version}")
        tools[name] = version
    if not re.fullmatch(r"[0-9a-f]{64}", registry_sha256):
        die("invalid Mason registry SHA-256")
    return {"registryVersion": registry_version, "registrySha256": registry_sha256, "tools": tools}


def latest_mason_pins() -> dict:
    release = fetch_json("https://api.github.com/repos/mason-org/mason-registry/releases/latest")
    version = str(release.get("tag_name", ""))
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"\d{4}-\d{2}-\d{2}-[a-z]+-[a-z]+", version):
        die(f"unexpected Mason registry release: {version}")
    asset = github_asset(release, "registry.json.zip")
    with tempfile.TemporaryDirectory(prefix="dotfiles-mason-registry-") as temporary:
        archive = Path(temporary) / "registry.json.zip"
        download_twice(asset["browser_download_url"], archive)
        registry_sha256 = sha256(archive)
        digest = asset.get("digest")
        if digest and digest != f"sha256:{registry_sha256}":
            die("Mason registry GitHub digest mismatch")
        with zipfile.ZipFile(archive) as source:
            if source.namelist() != ["registry.json"]:
                die("unexpected Mason registry archive entries")
            registry = json.loads(source.read("registry.json"))
    if not isinstance(registry, list):
        die("invalid Mason registry document")
    return mason_pins_from_registry(version, registry_sha256, registry)


def update_neovim(repo: Path) -> None:
    lock_path = repo / "config/shared/config/nvim/lazy-lock.json"
    lazy_expression = (
        f'let f = builtins.getFlake "path:{repo}"; '
        "in (import f.inputs.nixpkgs { system = builtins.currentSystem; }).vimPlugins.lazy-nvim"
    )
    lazy = run("nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr", lazy_expression)
    with tempfile.TemporaryDirectory(prefix="dotfiles-neovim-") as temporary:
        root = Path(temporary)
        config_home = root / "config"
        config = config_home / "nvim"
        shutil.copytree(repo / "config/shared/config/nvim", config)
        lazy_root = root / "data/nvim/site/pack/pins/start"
        lazy_root.mkdir(parents=True)
        os.symlink(lazy.splitlines()[-1], lazy_root / "lazy.nvim")
        environment = os.environ.copy()
        environment.update({
            "XDG_CONFIG_HOME": str(config_home),
            "XDG_DATA_HOME": str(root / "data"),
            "XDG_STATE_HOME": str(root / "state"),
            "XDG_CACHE_HOME": str(root / "cache"),
        })
        result = subprocess.run(
            (
                "nvim", "--headless",
                "+lua require('config.sync').plugins(false)",
                "+Lazy! update", "+qa",
            ),
            cwd=repo,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=600,
        )
        if result.returncode:
            die(f"Neovim plugin update failed: {result.stderr.strip()}")
        lock = json.loads((config / "lazy-lock.json").read_text(encoding="utf-8"))

    invalid = [name for name, value in lock.items() if not re.fullmatch(r"[0-9a-f]{40}", str(value.get("commit", "")))]
    if invalid:
        die(f"invalid Neovim lock commits: {invalid}")
    compact_lock = "{\n" + ",\n".join(
        f"  {json.dumps(name)}: {json.dumps(value, separators=(',', ': '))}"
        for name, value in lock.items()
    ) + "\n}\n"
    atomic_text(lock_path, compact_lock)
    mason_path = repo / "config/shared/config/nvim/mason-tools.json"
    mason = latest_mason_pins()
    atomic_json(mason_path, mason)
    print(f"updated {len(lock)} Neovim plugin pins and {len(mason['tools'])} Mason tool pins")


def main() -> int:
    if len(sys.argv) < 3:
        print(f"Usage: {Path(sys.argv[0]).name} TARGET [TARGET ...] REPO", file=sys.stderr)
        return 2
    targets, repo_arg = sys.argv[1:-1], sys.argv[-1]
    repo = Path(repo_arg).resolve()
    handlers = {
        "pi-extensions": update_pi_extensions,
        "webcord": update_webcord,
        "anki-zoom": update_anki_zoom,
        "firacode": update_firacode,
        "skills": update_skills,
        "neovim": update_neovim,
    }
    for target in targets:
        handler = handlers.get(target)
        if handler is None:
            print(f"Unknown pin target: {target}", file=sys.stderr)
            return 2
        try:
            handler(repo)
        except Exception as error:
            print(f"pin update failed for {target}: {error}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
