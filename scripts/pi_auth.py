#!/usr/bin/env python3
"""Check Pi credentials and complete missing logins in the terminal."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

PROVIDERS = {"openai-codex": {"oauth"}, "openrouter": {"api_key", "oauth"}}


def missing_providers(pi, env):
    missing = []
    for provider, auth_types in PROVIDERS.items():
        result = subprocess.run(
            [pi, "auth", "check", "--provider", provider, "--json", "--no-refresh"],
            env=env, capture_output=True, text=True, timeout=30, check=False,
        )
        # Never relay raw auth output, even on failure.
        try:
            status = json.loads(result.stdout)
        except (ValueError, TypeError) as error:
            raise RuntimeError(f"Pi returned an invalid auth status for {provider}.") from error
        if not isinstance(status, dict):
            raise RuntimeError(f"Pi returned an invalid auth status for {provider}.")
        auth_type = status.get("authType")
        if result.returncode == 0 and status.get("status") == "ready" and auth_type in auth_types:
            print(f"Pi {provider}: ready ({auth_type}).", flush=True)
        else:
            missing.append(provider)
    return missing


def package_directory(pi):
    # debt: support managed Nix/npm/Windows layouts; add a native locator for any new packaging layout.
    executable = Path(pi).resolve()
    candidates = []
    if os.environ.get("PI_PACKAGE_DIR"):
        candidates.append(Path(os.environ["PI_PACKAGE_DIR"]))
    # The managed Windows launcher names its immutable release explicitly.
    if executable.suffix.lower() == ".cmd":
        with executable.open(encoding="utf-8-sig") as launcher:
            match = re.search(r'(?mi)^node "(.+)[\\/]dist[\\/]bundle[\\/]cli\.js" %\*\s*$', launcher.read(16384))
        if match:
            candidates.append(Path(match.group(1)))
    # npm uses a direct entry-point link; Nix wraps a lib/node_modules installation.
    for parent in list(executable.parents)[:4]:
        candidates.extend([parent, parent / "lib/node_modules/@earendil-works/pi-coding-agent",
                           parent / "node_modules/@earendil-works/pi-coding-agent"])
    for candidate in candidates:
        manifest = candidate / "package.json"
        if not manifest.is_file():
            continue
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if data.get("name") == "@earendil-works/pi-coding-agent" and (candidate / "dist/core/auth-storage.js").is_file():
            return candidate.resolve()
    raise RuntimeError("Cannot locate Pi's installed authentication library; no login was started.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check only; never start login")
    args = parser.parse_args()
    pi = shutil.which("pi")
    if pi is None:
        raise RuntimeError("Pi is not on PATH; finish package setup and open a new terminal.")
    env = dict(os.environ, PI_OFFLINE="1")
    missing = missing_providers(pi, env)
    if not missing:
        return 0
    print("Pi authentication is needed for: " + ", ".join(missing), flush=True)
    if args.check or not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("Run dotfile pi-auth (Windows: ./dotfile.ps1 pi-auth) in a local terminal to finish setup.", file=sys.stderr)
        return 1
    node = shutil.which("node")
    if node is None:
        raise RuntimeError("Node is not on PATH; finish package setup and open a new terminal.")
    # Reuse the installed native OAuth and locked credential store, not its dev CLI writer.
    result = subprocess.run(
        [node, str(Path(__file__).with_name("pi_auth_login.mjs")), str(package_directory(pi)), *missing],
        env=env, timeout=900, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("Pi terminal login did not complete; rerun pi-auth to check the current state.")
    if missing_providers(pi, env):
        raise RuntimeError("Pi authentication is still incomplete; rerun pi-auth to finish the missing login.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        # OS/provider exceptions can include sensitive subprocess details.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print(f"Pi setup failed: {message}", file=sys.stderr)
        sys.exit(1)
