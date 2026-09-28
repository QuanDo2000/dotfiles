#!/usr/bin/env python3
"""Compare the installed-path source script and Rust candidate with private fixtures."""
import json
import os
import pathlib
import subprocess
import tempfile

repo = pathlib.Path(__file__).resolve().parents[2]
old = repo / 'scripts/hyprsunset-status.sh'
new = pathlib.Path(os.environ.get('HYPRSUNSET_CANDIDATE', repo / 'rust/hyprsunset-status/target/debug/hyprsunset-status'))
scenarios = [
    ('default-disabled', None, 'false', '12:00'),
    ('default-day', None, 'true', '07:00'),
    ('default-night-boundary', None, 'true', '20:00'),
    ('default-before-day', None, 'true', '06:59'),
    ('default-after-night', None, 'true', '20:01'),
    ('custom-day', 'time = 05:35\ntime = 21:15\ntemperature = 4200\n', 'true', '05:35'),
    ('custom-night', 'time = 05:35\ntime = 21:15\ntemperature = 4200\n', 'true', '21:15'),
    ('escaped-temp', 'time = 07:00\ntime = 20:00\ntemperature = 45"00\\\b\n', 'true', '21:00'),
    ('duplicate-temp', 'time = 07:00\ntime = 20:00\ntemperature = 3000\ntemperature = 4500\n', 'true', '21:00'),
    ('empty-last-temp', 'time = 07:00\ntime = 20:00\ntemperature = 3000\ntemperature =\n', 'true', '21:00'),
    ('fifo-config', '__FIFO__', 'true', '21:00'),
]
with tempfile.TemporaryDirectory(prefix='hyprsunset-oracle-', dir=os.environ['TMPDIR']) as raw:
    root = pathlib.Path(raw)
    for name, config, running, now in scenarios:
        home = root / name
        home.mkdir()
        if config is not None:
            conf = home / 'config/hypr/hyprsunset.conf'
            conf.parent.mkdir(parents=True)
            if config == '__FIFO__':
                os.mkfifo(conf)
            else:
                conf.write_text(config)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'), HYPRSUNSET_RUNNING=running)
        def call(command):
            out = subprocess.run([str(command), now], capture_output=True, text=True, env=env, timeout=5)
            assert out.returncode == 0, (name, command, out.stderr)
            return json.loads(out.stdout)
        expected = call(old)
        actual = call(new)
        assert actual == expected, (name, expected, actual)
        assert set(actual) == {'text', 'tooltip', 'class'}, (name, actual)
    # Exercise the real subprocess fallback with isolated fake commands, not a live user service.
    home = root / 'subprocess-fallback'
    bin_dir = home / 'bin'
    bin_dir.mkdir(parents=True)
    (bin_dir / 'systemctl').write_text('#!/bin/sh\nexit "${FAKE_SERVICE_EXIT:-0}"\n')
    (bin_dir / 'date').write_text('#!/bin/sh\nprintf "21:00\\n"\n')
    for command in ('systemctl', 'date'):
        (bin_dir / command).chmod(0o755)
    for code, expected_class in [('0', 'active'), ('3', 'disabled')]:
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'),
                   PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], FAKE_SERVICE_EXIT=code)
        env.pop('HYPRSUNSET_RUNNING', None)
        def fallback(command):
            out = subprocess.run([str(command)], capture_output=True, text=True, env=env, timeout=5)
            assert out.returncode == 0, (command, out.stderr)
            return json.loads(out.stdout)
        assert fallback(new) == fallback(old)
        assert fallback(new)['class'] == expected_class
    slow_home = root / 'inherited-pipe'
    slow_bin = slow_home / 'bin'
    slow_bin.mkdir(parents=True)
    slow_date = slow_bin / 'date'
    slow_date.write_text('#!/bin/sh\nsleep 10 &\nprintf "21:00\\n"\n')
    slow_date.chmod(0o755)
    env = dict(os.environ, HOME=str(slow_home), XDG_CONFIG_HOME=str(slow_home / 'config'),
               HYPRSUNSET_RUNNING='true', PATH=str(slow_bin) + os.pathsep + os.environ['PATH'])
    out = subprocess.run([str(new)], capture_output=True, text=True, env=env, timeout=6)
    assert out.returncode != 0 and 'timed out' in out.stderr, (out.returncode, out.stdout, out.stderr)
    print(f'HYPRSUNSET_ORACLE_PASS: {len(scenarios)} private CLI, 2 subprocess, 1 inherited-pipe scenario')
