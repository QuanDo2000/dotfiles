#!/usr/bin/env python3
"""Focused destructive-boundary checks; live API checks are run separately."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "retention", Path(__file__).resolve().parents[2] / "scripts/qbittorrent-calendar-retention.py"
)
assert SPEC and SPEC.loader
retention = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(retention)
NOW = 1800000000


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.torrent = {
            "hash": "a" * 40, "progress": 1, "amount_left": 0, "state": "queuedUP",
            "completion_on": NOW - retention.AGE_SECONDS, "content_path": "/downloads/old.mkv",
        }

    def plan(self, records=None):
        return retention.candidates([self.torrent] if records is None else records, NOW, self.root)

    def test_calendar_boundary_not_accumulated_seed_time(self):
        self.torrent["seeding_time"] = 0
        self.assertEqual(1, len(self.plan()))
        self.torrent["completion_on"] += 1
        self.assertFalse(self.plan())

    def test_incomplete_checking_and_unknown_completion_are_preserved(self):
        for changes in [{"progress": 0.9}, {"amount_left": 1}, {"state": "checkingUP"}, {"completion_on": 0}]:
            with self.subTest(changes=changes):
                torrent = self.torrent | changes
                self.assertFalse(self.plan([torrent]))

    def test_unowned_paths_are_rejected(self):
        for path in ["/downloads", "/downloads/../library/movie", "/movies/a.mkv", "/downloads2/a"]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.plan([self.torrent | {"content_path": path}])
        (self.root / "old.mkv").symlink_to(self.root / "elsewhere")
        with self.assertRaises(ValueError):
            self.plan()

    def test_shared_parent_and_child_paths_are_rejected(self):
        for other_path in ["/downloads/old.mkv", "/downloads", "/downloads/old.mkv/child"]:
            other = self.torrent | {"hash": "b" * 40, "content_path": other_path, "progress": 0.5}
            with self.subTest(path=other_path), self.assertRaises(ValueError):
                self.plan([self.torrent, other])

    def test_incomplete_torrent_alias_is_rejected(self):
        (self.root / "old.mkv").mkdir()
        (self.root / "link").symlink_to(self.root / "old.mkv", target_is_directory=True)
        other = self.torrent | {
            "hash": "b" * 40, "content_path": "/downloads/link/unfinished.mkv", "progress": 0.5,
        }
        with self.assertRaises(ValueError):
            self.plan([self.torrent, other])

    def test_malformed_ids_timestamps_and_large_batches_are_rejected(self):
        for changes in [{"hash": "all"}, {"completion_on": "yesterday"}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.plan([self.torrent | changes])
        with self.assertRaises(ValueError):
            self.plan([self.torrent, copy.copy(self.torrent)])
        records = [self.torrent | {"hash": f"{i:040x}", "content_path": f"/downloads/{i}"} for i in range(101)]
        with self.assertRaises(ValueError):
            self.plan(records)

    def test_changed_plan_never_posts(self):
        changed = self.torrent | {"completion_on": NOW}
        with patch.object(retention, "ROOT", self.root), patch.object(retention.time, "time", return_value=NOW):
            with patch.object(retention, "api", side_effect=[[self.torrent], [changed]]) as api:
                with self.assertRaises(RuntimeError):
                    retention.run(True)
                self.assertEqual([("torrents/info",), ("torrents/info",)], [c.args for c in api.call_args_list])

    def test_delete_requests_content_and_requires_readback(self):
        with patch.object(retention, "ROOT", self.root), patch.object(retention.time, "time", return_value=NOW):
            with patch.object(retention, "api", side_effect=[[self.torrent], [self.torrent], None, []]) as api:
                retention.run(True)
                self.assertEqual(("torrents/delete", {"hashes": "a" * 40, "deleteFiles": "true"}), api.call_args_list[2].args)
                self.assertEqual(("torrents/info",), api.call_args_list[3].args)
        (self.root / "old.mkv").touch()
        with patch.object(retention, "ROOT", self.root), patch.object(retention.time, "time", return_value=NOW):
            with patch.object(retention.time, "sleep"), patch.object(retention, "api", side_effect=[[self.torrent], [self.torrent], None] + [[]] * 12):
                with self.assertRaises(RuntimeError):
                    retention.run(True)


if __name__ == "__main__":
    unittest.main()
