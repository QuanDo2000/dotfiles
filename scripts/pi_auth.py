#!/usr/bin/env python3
"""Check Pi credentials and guide missing-provider setup through its native UI."""

import argparse
import json
import os
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check only; never open the login UI")
    args = parser.parse_args()
    pi = shutil.which("pi")
    if pi is None:
        raise RuntimeError("Pi is not on PATH; finish package setup and open a new terminal.")
    env = dict(os.environ, PI_OFFLINE="1")
    missing = missing_providers(pi, env)
    if not missing:
        return 0
    print("Pi authentication is needed. In Pi, run:", flush=True)
    for provider in missing:
        print(f"  /login {provider}", flush=True)
    print("Approve the Codex subscription link in your browser; enter OpenRouter keys only in Pi's login UI.", flush=True)
    print("Then exit Pi with /quit so setup can verify both providers.", flush=True)
    if args.check or not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("Run dotfile pi-auth (Windows: ./dotfile.ps1 pi-auth) in a local terminal to finish setup.", file=sys.stderr)
        return 1
    # Native Pi owns OAuth callbacks, secret entry and credential persistence.
    result = subprocess.run(
        [pi, "--offline", "--no-session", "--no-extensions", "--no-mcp", "--no-skills",
         "--no-prompt-templates", "--no-context-files", "--no-approve", "--no-tools"],
        env=env, timeout=900, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("Pi login UI did not exit successfully; existing credentials were not overwritten by setup.")
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
