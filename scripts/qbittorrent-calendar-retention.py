#!/usr/bin/env python3
"""Remove completed /downloads torrents after 30 calendar days; dry-run by default.

Use the existing VPN namespace's localhost-only authentication bypass. Never log
raw API responses: they contain magnet/tracker credentials. Native ratio/seeding
limits remain qBittorrent's responsibility, not a second implementation here.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import re
import resource
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlencode

ROOT = Path.home() / "Downloads/Torrent"
AGE_SECONDS = 30 * 86400
MAX_OUTPUT = 16 * 1024 * 1024
MAX_TORRENTS = 2000
MAX_DELETE = 100
COMPLETE_STATES = {"uploading", "stalledUP", "queuedUP", "stoppedUP", "pausedUP", "forcedUP"}


def limit_output():
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT, MAX_OUTPUT))


def api(endpoint, data=None):
    args = ["/usr/bin/docker", "exec", "protonvpn", "wget", "-qO-", "--timeout=15"]
    if data is not None:
        args += ["--post-data", urlencode(data)]
    args += ["http://127.0.0.1:8080/api/v2/" + endpoint]
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(
            args, stdout=output, stderr=subprocess.DEVNULL,
            timeout=20, check=False, preexec_fn=limit_output,
        )
        if result.returncode:
            raise RuntimeError(f"qBittorrent request failed: {endpoint}")
        output.seek(0)
        payload = output.read(MAX_OUTPUT + 1)
    if len(payload) >= MAX_OUTPUT:
        raise RuntimeError("qBittorrent response limit reached")
    if data is not None:
        if payload.strip():
            raise RuntimeError(f"Unexpected qBittorrent write response: {endpoint}")
        return None
    return json.loads(payload)


def candidates(torrents, now, root):
    if not isinstance(torrents, list) or len(torrents) > MAX_TORRENTS:
        raise ValueError("Invalid or oversized torrent inventory")
    seen = set()
    paths = {}
    # Validate aliases for EVERY torrent, including incomplete ones: an alias in
    # another torrent can hide its dependency on an expired torrent's directory.
    for torrent in torrents:
        torrent_hash = torrent["hash"]
        if not isinstance(torrent_hash, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", torrent_hash):
            raise ValueError("Invalid torrent identifier")
        if torrent_hash in seen:
            raise ValueError("Duplicate torrent identifier")
        seen.add(torrent_hash)
        raw = torrent["content_path"]
        if not isinstance(raw, str) or ".." in PurePosixPath(raw).parts:
            raise ValueError("Invalid torrent content path")
        path = PurePosixPath(raw)
        if not path.is_relative_to("/downloads") or path == PurePosixPath("/downloads"):
            raise ValueError("Torrent inventory is outside the download root")
        local = root / path.relative_to("/downloads")
        if local.resolve() != local.absolute() or not local.resolve().is_relative_to(root.resolve()):
            raise ValueError("Refusing aliased or symlinked torrent content")
        paths[torrent_hash] = (path, local)
    expired = {}
    for torrent in torrents:
        torrent_hash = torrent["hash"]
        completed = torrent["completion_on"]
        if type(completed) is not int:
            raise ValueError("Invalid completion timestamp")
        if (torrent["progress"] != 1 or torrent["amount_left"] != 0
                or torrent["state"] not in COMPLETE_STATES or completed <= 0
                or completed > now - AGE_SECONDS):
            continue
        path, local = paths[torrent_hash]
        for other in torrents:
            other_path, _ = paths[other["hash"]]
            if other["hash"] != torrent_hash and (
                other_path.is_relative_to(path) or path.is_relative_to(other_path)
            ):
                raise ValueError("Torrent content overlaps another torrent")
        expired[torrent_hash] = {"path": str(local), "completed": completed}
    if len(expired) > MAX_DELETE:
        raise ValueError("Deletion batch exceeds 100; review the backlog manually")
    return expired


def run(apply):
    now = int(time.time())
    planned = candidates(api("torrents/info"), now, ROOT)
    print(json.dumps({"mode": "apply" if apply else "dry-run", "expired": len(planned)}), flush=True)
    if not apply or not planned:
        return
    # A changed timestamp/path, new overlap or changed eligibility aborts the batch.
    if candidates(api("torrents/info"), now, ROOT) != planned:
        raise RuntimeError("Torrent inventory changed; refusing stale deletion plan")
    api("torrents/delete", {"hashes": "|".join(planned), "deleteFiles": "true"})
    for attempt in range(12):
        current = api("torrents/info")
        candidates(current, int(time.time()), ROOT)  # Validate the readback too.
        if not isinstance(current, list):
            raise ValueError("Invalid torrent inventory readback")
        remaining = {t["hash"] for t in current}
        client_pending = set(planned) & remaining
        source_pending = any(Path(t["path"]).exists() for t in planned.values())
        if not client_pending and not source_pending:
            print(json.dumps({"removed_and_source_absent": len(planned)}), flush=True)
            return
        if attempt < 11:
            time.sleep(2)
    raise RuntimeError("Deletion not fully verified; inspect client and source paths")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="delete expired torrent entries AND their source")
    args = parser.parse_args()
    try:
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        with (runtime / "qbittorrent-calendar-retention.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            run(args.apply)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.TimeoutExpired) as error:
        # Exception text may embed untrusted JSON or file contents; report only its type.
        print(f"Calendar retention failed ({type(error).__name__}); no blind retry", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
