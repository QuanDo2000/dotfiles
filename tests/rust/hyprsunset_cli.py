#!/usr/bin/env python3
"""Exercise the built status command in disposable, bounded scenarios."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

candidate = Path(os.environ['HYPRSUNSET_CANDIDATE'])
with tempfile.TemporaryDirectory(prefix='hyprsunset-cli-', dir=os.environ['TMPDIR']) as raw:
    root = Path(raw)
    config = root / 'config/hypr/hyprsunset.conf'
    config.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'), HYPRSUNSET_RUNNING='true')

    def run(*args):
        return subprocess.run([str(candidate), *args], capture_output=True, text=True, env=env, timeout=6)

    for time, expected in [('07:00', 'inactive'), ('20:00', 'active')]:
        result = run(time)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)['class'] == expected

    config.write_text('time = 05:35\ntime = 21:15\ntemperature = 45"00\\\b\n')
    result = run('21:15')
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['tooltip'] == 'Night light: 45"00\\\bK\nNormal colors at 05:35'
    config.unlink()
    os.mkfifo(config)
    result = run('21:00')
    assert result.returncode == 0 and json.loads(result.stdout)['class'] == 'active', result.stderr

    bin_dir = root / 'bin'
    bin_dir.mkdir()
    date = bin_dir / 'date'
    date.write_text('#!/bin/sh\nprintf "21:00\\n"\n')
    date.chmod(0o755)
    systemctl = bin_dir / 'systemctl'
    systemctl.write_text('#!/bin/sh\nexit "$FAKE_SERVICE_EXIT"\n')
    systemctl.chmod(0o755)
    env['PATH'] = str(bin_dir) + os.pathsep + os.environ['PATH']
    env.pop('HYPRSUNSET_RUNNING')
    for code, expected in [('0', 'active'), ('3', 'disabled')]:
        env['FAKE_SERVICE_EXIT'] = code
        result = run()
        assert result.returncode == 0 and json.loads(result.stdout)['class'] == expected, result.stderr

    env['HYPRSUNSET_RUNNING'] = 'true'
    date.write_text('#!/bin/sh\nsleep 10 &\nprintf "21:00\\n"\n')
    result = run()
    assert result.returncode != 0 and 'timed out' in result.stderr, (result.returncode, result.stderr)
print('hyprsunset CLI checks passed')
