"""Real CLI/subprocess checks; fake nix is confined to a disposable PATH."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/update_pins.py'
HASH = 'sha256-' + 'A' * 43 + '='
FAKE_NIX = '''#!{python}
import os, signal, sys, time
from pathlib import Path
if sys.argv[1] == 'eval':
    print('22.1.0')
    sys.exit(0)
assert sys.argv[1] == 'run', sys.argv
mode = os.environ['PREFETCH_MODE']
print('native nix diagnostic', file=sys.stderr, flush=True)
if mode == 'success':
    time.sleep(.25)
    print('earlier sha256-AAAA=')
    print({hash!r})
    sys.exit(0)
if mode == 'nonzero':
    print({hash!r})
    sys.exit(7)
if mode == 'missing':
    print('no digest')
    sys.exit(0)
if mode == 'overflow':
    sys.stdout.buffer.write(b'x' * (2 * 1024 * 1024))
    sys.stdout.flush()
else:
    child = os.fork()
    if child == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        Path(os.environ['CHILD_PID']).write_text(str(os.getpid()))
        while True: time.sleep(1)
    Path(os.environ['LEADER_PID']).write_text(str(os.getpid()))
    if mode == 'orphan':
        sys.exit(0)  # Descendant still owns the stdout pipe.
while True: time.sleep(1)
'''


@unittest.skipUnless(os.name == 'posix', 'POSIX process groups required')
class PiPrefetchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pi-prefetch-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.files = {
            'config/shared/ai/pi/extensions/package.json': json.dumps({'dependencies': {}}),
            'config/shared/ai/pi/extensions/package-lock.json': json.dumps({'packages': {}}),
            'packages/pi-extensions-release.json': json.dumps({'releaseId': 'old-release', 'node': {'version': '22.1.0', 'abi': '127'}}),
            'packages/pi-extensions.nix': 'npmDepsHash = "sha256-old=";\n',
            'config/shared/ai/pi/settings.json': '{"release": "old-release"}\n',
        }
        for relative, text in self.files.items():
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        binary = self.root / 'bin'
        binary.mkdir()
        nix = binary / 'nix'
        nix.write_text(FAKE_NIX.format(python=sys.executable, hash=HASH))
        nix.chmod(0o700)
        self.env = dict(os.environ, PATH=str(binary), TMPDIR=str(self.root),
                        DOTFILE_PREFETCH_TIMEOUT_SECONDS='1',
                        CHILD_PID=str(self.root / 'child'), LEADER_PID=str(self.root / 'leader'))
        self.processes = []
        self.addCleanup(self.cleanup_processes)

    def cleanup_processes(self):
        for process in self.processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)
        # Baseline has no dedicated prefetch session; clean its inherited group
        # above. Patched prefetch leaders have their own groups.
        leader = self.root / 'leader'
        if leader.exists():
            try:
                os.killpg(int(leader.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def start(self, mode, shortened_heartbeat=False):
        env = dict(self.env, PREFETCH_MODE=mode)
        command = [sys.executable, str(SCRIPT), 'pi-extensions', str(self.repo)]
        if shortened_heartbeat:
            command = [sys.executable, '-c',
                       'import sys; sys.path.insert(0, sys.argv.pop(1)); import update_pins; '
                       'update_pins.PREFETCH_HEARTBEAT_SECONDS=.05; '
                       'raise SystemExit(update_pins.main())', str(SCRIPT.parent),
                       'pi-extensions', str(self.repo)]
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.processes.append(process)
        return process

    def finish(self, process):
        try:
            out, err = process.communicate(timeout=7)
        except subprocess.TimeoutExpired:
            self.fail('outer watchdog: prefetch exceeded deadline plus cleanup allowance')
        return process.returncode, out, err

    def unchanged(self):
        for relative, text in self.files.items():
            self.assertEqual((self.repo / relative).read_text(), text, relative)

    def assert_child_stopped(self):
        pid = int((self.root / 'child').read_text())
        # Orphan zombies may await the host init reaper; they cannot run.
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            stat = Path(f'/proc/{pid}/stat')
            if stat.exists() and stat.read_text().split()[2] == 'Z':
                return
            time.sleep(.02)
        self.fail(f'prefetch descendant {pid} still running')

    def wait_child(self):
        deadline = time.monotonic() + 3
        while not (self.root / 'child').exists():
            self.assertLess(time.monotonic(), deadline, 'fixture did not start')
            time.sleep(.01)

    def test_stall_deadline_and_no_publication(self):
        process = self.start('stall', shortened_heartbeat=True)
        code, _, err = self.finish(process)
        self.assertEqual(code, 1, err)
        self.assertIn('Pi closure prefetch', err)
        self.assertIn('elapsed', err)
        self.assertIn('timed out', err)
        self.assertIn('native nix diagnostic', err)
        self.unchanged()
        self.assert_child_stopped()

    def test_deadline_includes_pipe_drain_after_leader_exits(self):
        code, _, err = self.finish(self.start('orphan'))
        self.assertEqual(code, 1, err)
        self.assertIn('timed out', err)
        self.unchanged()
        self.assert_child_stopped()

    def test_success_uses_last_exact_hash_and_visible_heartbeat(self):
        code, _, err = self.finish(self.start('success', shortened_heartbeat=True))
        self.assertEqual(code, 0, err)
        self.assertGreaterEqual(err.count('Pi closure prefetch'), 3)
        self.assertIn('native nix diagnostic', err)
        self.assertEqual((self.repo / 'packages/pi-extensions.nix').read_text(), f'npmDepsHash = "{HASH}";\n')
        release = json.loads((self.repo / 'packages/pi-extensions-release.json').read_text())
        digest = hashlib.sha256((self.repo / 'config/shared/ai/pi/extensions/package-lock.json').read_bytes()).hexdigest()
        self.assertEqual(release['releaseId'], digest)
        self.assertEqual(release['node'], {'version': '22.1.0', 'abi': '127'})
        self.assertIn(digest, (self.repo / 'config/shared/ai/pi/settings.json').read_text())

    def test_errors_do_not_publish(self):
        for mode, message in [('nonzero', 'exit status 7'), ('missing', 'returned no hash'), ('overflow', 'stdout exceeded')]:
            with self.subTest(mode=mode):
                code, _, err = self.finish(self.start(mode))
                self.assertEqual(code, 1, err)
                self.assertIn(message, err)
                self.unchanged()

    def test_cancellation_cleans_group_after_leader_exits(self):
        self.env['DOTFILE_PREFETCH_TIMEOUT_SECONDS'] = '30'
        for sig in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=sig):
                for name in ('child', 'leader'):
                    (self.root / name).unlink(missing_ok=True)
                process = self.start('stall')
                self.wait_child()
                process.send_signal(sig)
                code, _, err = self.finish(process)
                self.assertEqual(code, 128 + sig, err)
                self.unchanged()
                self.assert_child_stopped()

    def test_invalid_deadline_rejected_before_commands_or_writes(self):
        for value in ('0', '-1', '86401', '1.5', ''):
            with self.subTest(value=value):
                self.env['DOTFILE_PREFETCH_TIMEOUT_SECONDS'] = value
                code, _, err = self.finish(self.start('success'))
                self.assertEqual(code, 1, err)
                self.assertIn('DOTFILE_PREFETCH_TIMEOUT_SECONDS', err)
                self.unchanged()


if __name__ == '__main__':
    unittest.main()
