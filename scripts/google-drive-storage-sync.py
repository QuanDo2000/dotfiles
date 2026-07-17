#!/usr/bin/env python3
import argparse
import json
import os
import posixpath
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

RCLONE = os.environ.get("RCLONE", "rclone")
PAIRS = (
    ("Book", "gdrive:Drive/Book", "/mnt/storage/Storage/Book"),
    ("Documents", "gdrive:Drive/Documents", "/mnt/storage/Storage/Documents"),
)
REMOTE_BACKUP = "gdrive:.Storage-sync-backup"
STORAGE_BACKUP = Path("/mnt/storage/Storage/.Drive-sync-backup")
RETENTION_DAYS = 30


def rclone(*args, capture=False):
    return subprocess.run(
        [RCLONE, *args],
        check=True,
        text=True,
        capture_output=capture,
    )


def duplicate_report(result):
    return "\n".join(part.strip() for part in (result.stdout, result.stderr) if part and part.strip())


def ensure_no_duplicates(root):
    report = duplicate_report(rclone("dedupe", "--dedupe-mode", "list", root, capture=True))
    if report:
        raise RuntimeError(f"duplicate Google Drive paths under {root}:\n{report}")


def inventory(root):
    items = json.loads(rclone("lsjson", root, "--recursive", "--no-mimetype", capture=True).stdout)
    dirs = {""}
    files = {}
    for item in items:
        path = item["Path"].rstrip("/")
        if item["IsDir"]:
            dirs.add(path)
        elif item.get("Size", -1) >= 0:
            files[path] = (item["Size"], datetime.fromisoformat(item["ModTime"].replace("Z", "+00:00")).timestamp())
    return dirs, files


def make_plan(remote_dirs, remote_files, storage_dirs, storage_files):
    common_dirs = remote_dirs & storage_dirs

    # ponytail: fixed policy filter; add configuration only when another policy exists.
    def allowed(path):
        name = posixpath.basename(path)
        return not (
            any(part.casefold() == "recovery" for part in posixpath.dirname(path).split("/"))
            or name.startswith("._")
            or name == ".DS_Store"
            or name.lower().endswith((".iso", ".pfx"))
        )

    remote = {
        p: v
        for p, v in remote_files.items()
        if posixpath.dirname(p) in common_dirs and allowed(p)
    }
    storage = {
        p: v
        for p, v in storage_files.items()
        if posixpath.dirname(p) in common_dirs and allowed(p)
    }
    plan = {
        "down": set(),
        "up": set(),
        "backup_storage": set(),
        "backup_remote": set(),
        "conflicts": set(),
        "same": 0,
        "common_dirs": len(common_dirs),
        "skipped_remote": len(remote_files) - len(remote),
        "skipped_storage": len(storage_files) - len(storage),
    }
    for path in sorted(remote.keys() | storage.keys()):
        if "\n" in path:
            raise ValueError(f"newline in path is unsupported: {path!r}")
        if path not in storage:
            plan["down"].add(path)
        elif path not in remote:
            plan["up"].add(path)
        elif remote[path][0] == storage[path][0]:
            plan["same"] += 1
        elif remote[path][1] > storage[path][1]:
            plan["backup_storage"].add(path)
            plan["down"].add(path)
        elif storage[path][1] > remote[path][1]:
            plan["backup_remote"].add(path)
            plan["up"].add(path)
        else:
            plan["conflicts"].add(path)
    plan["down_bytes"] = sum(remote[path][0] for path in plan["down"])
    plan["up_bytes"] = sum(storage[path][0] for path in plan["up"])
    return plan


def copy_files(source, destination, paths):
    if not paths:
        return
    with tempfile.NamedTemporaryFile("w", encoding="utf-8") as file_list:
        file_list.write("\n".join(sorted(paths)) + "\n")
        file_list.flush()
        rclone("copy", source, destination, "--files-from-raw", file_list.name, "--create-empty-src-dirs")


def cleanup_backups(now):
    cutoff = now - timedelta(days=RETENTION_DAYS)
    STORAGE_BACKUP.mkdir(parents=True, exist_ok=True)
    rclone("mkdir", REMOTE_BACKUP)

    for path in STORAGE_BACKUP.iterdir():
        if path.is_dir() and parse_backup_time(path.name, cutoff):
            shutil.rmtree(path)

    listing = rclone("lsf", REMOTE_BACKUP, "--dirs-only", "--max-depth", "1", capture=True).stdout
    for name in listing.splitlines():
        name = name.rstrip("/")
        if parse_backup_time(name, cutoff):
            rclone("purge", f"{REMOTE_BACKUP}/{name}")


def parse_backup_time(name, cutoff):
    try:
        return datetime.strptime(name, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc) < cutoff
    except ValueError:
        return False


def sync_pair(name, remote_root, storage_root, stamp, dry_run):
    ensure_no_duplicates(remote_root)
    remote_dirs, remote_files = inventory(remote_root)
    storage_dirs, storage_files = inventory(storage_root)
    plan = make_plan(remote_dirs, remote_files, storage_dirs, storage_files)
    print(
        f"{name}: common_dirs={plan['common_dirs']} down={len(plan['down'])} "
        f"down_bytes={plan['down_bytes']} up={len(plan['up'])} up_bytes={plan['up_bytes']} "
        f"replace_storage={len(plan['backup_storage'])} "
        f"replace_drive={len(plan['backup_remote'])} same={plan['same']} "
        f"conflicts={len(plan['conflicts'])} skipped_remote={plan['skipped_remote']} "
        f"skipped_storage={plan['skipped_storage']}"
    )
    if dry_run:
        return len(plan["conflicts"])

    local_backup = str(STORAGE_BACKUP / stamp / name)
    remote_backup = f"{REMOTE_BACKUP}/{stamp}/{name}"
    copy_files(storage_root, local_backup, plan["backup_storage"])
    copy_files(remote_root, remote_backup, plan["backup_remote"])
    copy_files(remote_root, storage_root, plan["down"])
    copy_files(storage_root, remote_root, plan["up"])
    for path in sorted(plan["conflicts"]):
        print(f"{name}: equal-time size conflict skipped: {path}", file=sys.stderr)
    return len(plan["conflicts"])


def self_test():
    old, new = 100.0, 200.0
    plan = make_plan(
        {"", "shared", "shared/Recovery", "remote-only"},
        {
            "shared/down": (2, new),
            "shared/replace": (3, new),
            "shared/.DS_Store": (9, new),
            "remote-only/skip": (1, new),
        },
        {"", "shared", "shared/Recovery", "storage-only"},
        {
            "shared/up": (4, new),
            "shared/replace": (1, old),
            "shared/skip.iso": (9, new),
            "shared/._skip": (9, new),
            "shared/secret.PFX": (9, new),
            "shared/Recovery/skip.txt": (9, new),
            "storage-only/skip": (1, new),
        },
    )
    assert plan["down"] == {"shared/down", "shared/replace"}
    assert plan["up"] == {"shared/up"}
    assert plan["backup_storage"] == {"shared/replace"}
    assert plan["backup_remote"] == set()
    assert plan["down_bytes"] == 5 and plan["up_bytes"] == 4
    assert plan["skipped_remote"] == 2 and plan["skipped_storage"] == 5
    cutoff = datetime(2026, 2, 1, tzinfo=timezone.utc)
    assert parse_backup_time("20260101T000000Z", cutoff)
    assert not parse_backup_time("20260301T000000Z", cutoff)
    assert not parse_backup_time("keep-me", cutoff)
    assert duplicate_report(subprocess.CompletedProcess([], 0, "", "")) == ""
    assert duplicate_report(subprocess.CompletedProcess([], 0, "duplicate", "")) == "duplicate"
    print("SELF_TEST_OK")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return

    # ponytail: filename and size are intentional; equal-size content differences are out of scope.
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    conflicts = sum(sync_pair(*pair, stamp, args.dry_run) for pair in PAIRS)
    if not args.dry_run:
        cleanup_backups(now)
    if conflicts:
        raise SystemExit(f"{conflicts} equal-time conflicts require manual review")


if __name__ == "__main__":
    main()
