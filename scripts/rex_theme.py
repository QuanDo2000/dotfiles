#!/usr/bin/env python3
"""Seed Rex's theme once through its native local-client action."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import quote


class Unavailable(Exception):
    pass


def call(rex: str, endpoint: str, *args: str) -> dict:
    result = subprocess.run(
        [rex, "--server", endpoint, "--autostart=false", "--timeout", "3s", *args],
        capture_output=True, text=True, timeout=5, check=False,
    )
    if result.returncode == 4:
        raise Unavailable("local server is not running")
    if result.returncode != 0:
        if "code=refused" in result.stderr:
            raise Unavailable("local app refused the action; enable Remote Control in Rex Settings > Rex Server, then retry")
        # Do not publish arbitrary client output or private server diagnostics.
        raise RuntimeError(f"Rex command failed (exit {result.returncode}); no completion marker written")
    if len(result.stdout) > 1024 * 1024:
        raise RuntimeError("Rex reply exceeds 1 MiB")
    reply = json.loads(result.stdout)
    if not isinstance(reply, dict):
        raise RuntimeError("invalid Rex reply")
    return reply


def setup(rex: str, theme: Path) -> None:
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "dotfiles"
    if not state.is_absolute():
        raise RuntimeError("XDG_STATE_HOME must be absolute")
    state.mkdir(parents=True, exist_ok=True)
    marker = state / "rex-theme-initialized"
    with (state / "rex-theme.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return  # Another activation/shell owns this attempt.
        if marker.exists():
            with marker.open() as existing:
                value = existing.read(64)
            if value != "catppuccin-macchiato-v1\n":
                raise RuntimeError("unrecognized Rex theme marker; refusing to reset preferences")
            return
        if not theme.is_file():
            raise RuntimeError("managed Rex theme file is missing")
        # Never follow REX_SERVER, REX_HOME, or a remote host selection.
        socket = home / "Library/Application Support/rex/server.sock"
        endpoint = "unix://" + quote(str(socket))
        reply = call(rex, endpoint, "client", "ls", "--json")
        clients = reply.get("clients")
        if not isinstance(clients, list) or len(clients) > 256:
            raise RuntimeError("invalid or oversized Rex client list")
        apps = []
        for client in clients:
            if not isinstance(client, dict):
                raise RuntimeError("invalid Rex client")
            info = client.get("info", {})
            principal = client.get("principal", {})
            if not isinstance(info, dict) or not isinstance(principal, dict):
                raise RuntimeError("invalid Rex client metadata")
            if (info.get("kind") == "app" and info.get("platform") == "macos"
                    and principal.get("transport") == "unix" and principal.get("uid") == os.getuid()):
                apps.append(client)
        if len(apps) != 1:
            raise Unavailable("expected exactly one local macOS app; retry on the next Rex shell")
        client_id = apps[0].get("client_id")
        if not isinstance(client_id, str) or not client_id.startswith("client:"):
            raise RuntimeError("invalid Rex app ID")
        result = call(rex, endpoint, "api", "call", "client.perform", json.dumps({
            "client_id": client_id,
            "action": "client.theme.import",
            "args": {"path": str(theme.resolve())},
            "origin": "cli",
            "timeout_ms": 2000,
        }))
        if result.get("performed_by") != client_id:
            raise RuntimeError("Rex did not confirm the targeted app performed the import")
        # The native import action also selects the theme. Only successful
        # completion suppresses future attempts, preserving later user choices.
        with marker.open("x") as completed:
            completed.write("catppuccin-macchiato-v1\n")
        print("Rex: imported and selected Catppuccin Macchiato (one-time setup)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rex", required=True)
    parser.add_argument("--theme", type=Path, required=True)
    args = parser.parse_args()
    try:
        setup(args.rex, args.theme)
    except Unavailable as error:
        print(f"Rex theme setup deferred: {error}")
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Rex theme setup failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
