#!/usr/bin/env python3
"""Exercise managed Zsh hooks, real dotfile help/errors and harmless tool stand-ins."""
import errno
import fcntl
import os
import pathlib
import pty
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import termios
import time


def claim_terminal():
    # Popen has created the session and duped the slave onto stdin. Claim it
    # explicitly: setsid alone leaves Darwin Zsh without a controlling terminal.
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def run(config, home, rex, tmux, terminal):
    script = f"""
PROMPT=''
RPROMPT=''
gpg-connect-agent() {{ :; }}
source {shlex.quote(str(config))}
# Re-sourcing must not register duplicate hooks.
source {shlex.quote(str(config))}
iib() {{ printf 'fixture-output:%s\\n' "$*"; return "$1"; }}
cn2epub() {{ return "$1"; }}
{shlex.quote(str(config.parents[1].parent / 'dotfile'))} -h
{shlex.quote(str(config.parents[1].parent / 'dotfile'))} invalid-status-test-command
print -r -- "dotfile-exit:$?"
iib 7 private-argument
print -r -- "iib-exit:$?"
cn2epub 130
print -r -- "cancel-exit:$?"
iib 0 | cat
iib 0 && true
iib 0 &
wait
true
exit 0
"""
    env = {**os.environ, "HOME": str(home), "ZDOTDIR": str(home),
           "REX_BIN_DIR": str(home / 'rex-bin') if rex else '',
           "TMUX": 'fixture' if tmux else '', "NO_TMUX": '1',
           "TERM": 'xterm-256color', "PS1": '__REX_STATUS_READY__ '}
    master, slave = pty.openpty()
    process = None
    output = bytearray()
    try:
        process = subprocess.Popen(['zsh', '-dfi'], stdin=slave,
                                   stdout=slave if terminal else subprocess.PIPE,
                                   stderr=slave if terminal else subprocess.STDOUT,
                                   env=env, start_new_session=True,
                                   preexec_fn=claim_terminal)
        if terminal:
            output_fd = master
        else:
            assert process.stdout is not None
            output_fd = process.stdout.fileno()
        os.close(slave)
        slave = -1
        script_bytes = script.encode()
        assert len(script_bytes) < 4096
        sent = False
        read_fds = [master] if terminal else [master, output_fd]
        deadline = time.monotonic() + 15
        while read_fds and time.monotonic() < deadline:
            ready, _, _ = select.select(read_fds, [], [], 0.1)
            if not ready:
                if process.poll() is not None:
                    break
                continue
            for fd in ready:
                try:
                    data = os.read(fd, 8192)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b''
                if not data:
                    read_fds.remove(fd)
                    continue
                output.extend(data)
                # Zsh may write its initial prompt directly to /dev/tty even
                # with redirected stdout. Wait for tty setup before typeahead.
                if not sent and b'__REX_STATUS_READY__' in output:
                    assert os.write(master, script_bytes) == len(script_bytes)
                    sent = True
                if len(output) >= 65536:
                    raise RuntimeError('Zsh output exceeds capture limit')
        if process.poll() is None and time.monotonic() >= deadline:
            raise RuntimeError(f'Zsh deadline exceeded ({rex=}, {tmux=}, {terminal=}, {sent=}): {bytes(output[-4000:])!r}')
        assert process.wait(timeout=max(0.1, deadline - time.monotonic())) == 0
        return bytes(output)
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        if process is not None and process.stdout is not None:
            process.stdout.close()
        if slave != -1:
            os.close(slave)
        os.close(master)


def main():
    config = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory() as temp:
        home = pathlib.Path(temp)
        for rex, tmux, terminal in [(True, False, True), (False, False, True),
                                    (True, True, True), (True, False, False)]:
            output = run(config, home, rex, tmux, terminal)
            reports = re.findall(rb'\x1b\]7501;([^\x1b]*)\x1b\\', output)
            expected = []
            if rex and not tmux and terminal:
                expected = [b'state=working:app=dotfile', b'state=done:app=dotfile',
                            b'state=working:app=dotfile', b'state=error:app=dotfile',
                            b'state=working:app=iib', b'state=error:app=iib',
                            b'state=working:app=cn2epub', b'state=idle:app=cn2epub']
            assert reports == expected, (rex, tmux, terminal, reports, output[-2000:])
            for marker in [b'Usage:', b'dotfile-exit:1', b'iib-exit:7',
                           b'cancel-exit:130', b'fixture-output:7 private-argument']:
                assert marker in output, (marker, output[-2000:])
            assert all(b'private-argument' not in report for report in reports)
    print('PASS: Rex lifecycle reports, status/output preservation, compounds and terminal guards')


if __name__ == '__main__':
    main()
