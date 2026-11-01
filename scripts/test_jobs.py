#!/usr/bin/env python3
"""Run isolated test files with bounded concurrency and deterministic output.

Used inside the pinned Unix check shell, not by standalone platform runners.
Each command is its own process group; failures are collected without skipping
pending files. Retired commands and aborted work release their owned groups
before temporary logs are removed. Leaders stay waitable until the last group
signal, preventing PID/group identity reuse during cleanup. The parent bounds
persisted stdout/stderr and drains excess output during cancellation cleanup.
"""
import argparse
import json
import math
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time


MAX_FILES = 256
MAX_LOG_BYTES = 16 * 1024 * 1024
CLEANUP_SECONDS = 3
MAX_CLEANUP_SECONDS = 5


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--shared-run', action='store_true',
                        help='export a fresh owned run directory/root file index; nested ordinary jobs inherit them')
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--total-timeout', type=float, default=1800)
    parser.add_argument('--cleanup-seconds', type=float, default=CLEANUP_SECONDS,
                        help='TERM grace (0.1..5s, default 3s); nested coordinators must finish before their owner')
    parser.add_argument('--first', action='append', default=[], help='start this listed file early; preserve result order')
    parser.add_argument('--files', nargs='+', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if os.name != 'posix':
        parser.error('Unix gate helper requires POSIX process groups; use the native standalone runner')
    if not hasattr(os, 'waitid') or not hasattr(os, 'WNOWAIT'):
        parser.error('Unix gate helper requires waitid/WNOWAIT to retain group ownership')
    if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
        parser.error('Unix gate helper requires waitable children (default SIGCHLD)')
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be from 1 to 8')
    if not math.isfinite(args.timeout) or not 0.1 <= args.timeout <= 10800:
        parser.error('--timeout must be finite, from 0.1 to 10800 seconds')
    if not math.isfinite(args.total_timeout) or not 0.1 <= args.total_timeout <= 21600:
        parser.error('--total-timeout must be finite, from 0.1 to 21600 seconds')
    if not math.isfinite(args.cleanup_seconds) or not 0.1 <= args.cleanup_seconds <= MAX_CLEANUP_SECONDS:
        parser.error('--cleanup-seconds must be finite, from 0.1 to 5 seconds')
    if not 1 <= len(args.files) <= MAX_FILES or not 1 <= len(command) <= 16:
        parser.error('expected 1..256 files and a 1..16 argument command prefix')
    for file in args.files:
        if not Path(file).is_file():
            parser.error(f'test file does not exist: {file}')

    if len(args.first) > MAX_FILES or len(set(args.first)) != len(args.first):
        parser.error('--first must contain at most 256 unique file names')
    if any(file not in args.files for file in args.first):
        parser.error('--first files must also appear in --files')
    priorities = {file: index for index, file in enumerate(args.first)}
    execution_order = sorted(range(len(args.files)),
                             key=lambda index: (priorities.get(args.files[index], len(priorities)), index))

    interrupted = 0

    def interrupt(signum, _frame):
        nonlocal interrupted
        interrupted = signum

    original_handlers = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    active = {}
    results = {}
    observed_exits = {}
    next_file = 0
    started = time.monotonic()
    deadline = started + min(args.total_timeout, args.timeout * math.ceil(len(args.files) / args.jobs) + args.cleanup_seconds)
    failure = False
    aborted = None
    publication_failure_exit = None

    term_deadlines = {}
    output_bytes = {}
    output_done = set()
    overflowed = set()
    capture_errors = {}

    def capture_problem(index, message):
        nonlocal aborted
        capture_errors.setdefault(index, message)
        if aborted is None:
            aborted = f'output capture failed: {args.files[index]}: {message}'

    def drain_outputs():
        nonlocal aborted
        read_any = False
        for index, (process, log, _start, _index) in active.items():
            if index in output_done:
                continue
            # Bound work per iteration, not stream throughput. A busy stream
            # yields to deadline/signal/other-job checks after sixteen blocks.
            for _ in range(16):
                try:
                    if not select.select([process.stdout], [], [], 0)[0]:
                        break
                    block = os.read(process.stdout.fileno(), 65536)
                except OSError as error:
                    capture_problem(index, str(error))
                    output_done.add(index)
                    break
                if not block:
                    output_done.add(index)
                    break
                read_any = True
                remaining = MAX_LOG_BYTES - output_bytes[index]
                if index not in capture_errors and remaining:
                    prefix = block[:remaining]
                    try:
                        written = log.write(prefix)
                        output_bytes[index] += written
                        if written != len(prefix):
                            capture_problem(index, 'short spool write')
                    except OSError as error:
                        capture_problem(index, str(error))
                if len(block) > remaining:
                    overflowed.add(index)
                    if aborted is None:
                        aborted = f'output limit exceeded: {args.files[index]}'
                # Keep draining/discarding on overflow or persistence failure:
                # nested coordinators must retain their FULL cleanup grace.
        return read_any

    def close_output(process, log, index):
        for stream in (process.stdout, log):
            try:
                stream.close()
            except OSError as error:
                capture_problem(index, str(error))

    def running_groups(groups, seconds, cancelling=False):
        if not groups:
            return set()
        # -g selects sessions on GNU ps and groups on Darwin. Each owned
        # leader starts a fresh session with SID == PGID; filter PGIDs below.
        env = {**os.environ, 'COMMAND_MODE': 'unix2003',
               'PS_PERSONALITY': 'posix', 'LC_ALL': 'C'}
        probe = subprocess.Popen(['ps', '-g', ','.join(map(str, groups)), '-o', 'pgid=,stat='],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=env)
        data = bytearray()
        deadline = time.monotonic() + seconds
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or (interrupted and not cancelling):
                    raise RuntimeError('owned-group inspection interrupted or timed out')
                if not select.select([probe.stdout], [], [], min(remaining, 0.02))[0]:
                    continue
                block = os.read(probe.stdout.fileno(), 4096)
                if not block:
                    break
                data.extend(block)
                # debt: ownership snapshots <=64KiB; raise/revalidate if exceeded.
                if len(data) > 65536:
                    raise RuntimeError('owned-group inspection output limit exceeded')
            if probe.wait(timeout=max(0.001, deadline - time.monotonic())) != 0:
                raise RuntimeError('owned-group inspection failed')
        finally:
            if probe.poll() is None:
                probe.kill()
            probe.wait(timeout=1)
            probe.stdout.close()
        running, seen = set(), set()
        for line in data.splitlines():
            fields = line.split()
            if len(fields) != 2 or not fields[0].isdigit():
                raise RuntimeError('invalid owned-group inspection row')
            group = int(fields[0])
            if group in groups:
                seen.add(group)
                if not fields[1].startswith(b'Z'):
                    running.add(group)
        if seen != set(groups):
            raise RuntimeError('owned-group inspection lost an unreaped leader')
        return running

    def stop_groups():
        for process, _log, _start, index in active.values():
            if index not in term_deadlines:
                os.killpg(process.pid, signal.SIGTERM)
                term_deadlines[index] = time.monotonic() + args.cleanup_seconds
        grace = max(term_deadlines.values(), default=time.monotonic())
        inspection_failed = False
        while time.monotonic() < grace:
            read_any = drain_outputs()
            if not inspection_failed:
                try:
                    groups = {process.pid for process, *_rest in active.values()}
                    if (not running_groups(groups, min(0.1, max(0, grace - time.monotonic())), cancelling=True)
                            and all(index in output_done for index in active)):
                        break
                except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    # Without inspection retain every lease and the FULL grace:
                    # a nested coordinator may own separately grouped children.
                    print(f'Group cleanup inspection unavailable: {error}', file=sys.stderr)
                    inspection_failed = True
            if not read_any:
                time.sleep(min(0.02, max(0, grace - time.monotonic())))
        # Signal every still-leased group before reaping any leader. Never
        # inspect/signal a remembered PGID after releasing its leader lease.
        for process, _log, _start, _index in active.values():
            os.killpg(process.pid, signal.SIGKILL)
        for process, _log, _start, _index in active.values():
            process.wait(timeout=args.cleanup_seconds)
        drain_outputs()
        finished = list(active.items())
        active.clear()
        term_deadlines.clear()
        for index, (process, log, _start, _index) in finished:
            if index not in output_done:
                print(f'Output EOF not observed during aborted cleanup: {args.files[index]}', file=sys.stderr)
            close_output(process, log, index)

    def publish_json(path, data):
        pending = path.with_suffix('.pending')
        with pending.open('x') as output:
            json.dump(data, output)
            output.write('\n')
        pending.replace(path)

    try:
        with tempfile.TemporaryDirectory(prefix='dotfiles-test-jobs-') as directory:
            shared = Path(directory) / 'shared' if args.shared_run else None
            run_id = Path(directory).name
            if shared is not None:
                shared.mkdir()
                publish_json(shared / 'manifest.json', {
                    'protocol': 'test-jobs-run-v1', 'id': run_id, 'pid': os.getpid(),
                    'files': [str(Path(file).resolve()) for file in args.files]})
            try:
                while next_file < len(args.files) or active:
                    if interrupted:
                        aborted = f'interrupted by signal {interrupted}'
                        break
                    if time.monotonic() >= deadline:
                        aborted = 'overall test-job deadline exceeded'
                        break
                    while next_file < len(args.files) and len(active) < args.jobs:
                        index = execution_order[next_file]
                        path = Path(directory) / f'{index}.log'
                        log = path.open('wb', buffering=0)
                        scratch = Path(directory) / f'{index}.tmp'
                        scratch.mkdir()
                        # PowerShell's command-discovery cache otherwise lives
                        # under the real HOME and is shared by fresh engines.
                        env = {**os.environ, 'TMPDIR': str(scratch),
                               'PSModuleAnalysisCachePath': str(scratch / 'ps-module-cache')}
                        if shared is not None:
                            env.update(TEST_JOBS_SHARED_DIR=str(shared), TEST_JOBS_SHARED_ROLE=str(index))
                        try:
                            process = subprocess.Popen([*command, args.files[index]], stdout=subprocess.PIPE,
                                                       stderr=subprocess.STDOUT, start_new_session=True, env=env)
                        except OSError:
                            log.close()
                            raise
                        active[index] = (process, log, time.monotonic(), index)
                        output_bytes[index] = 0
                        next_file += 1
                    read_any = drain_outputs()
                    if aborted:
                        break
                    completed = []
                    for index, (process, log, job_start, _index) in list(active.items()):
                        # Observe exit without reaping: its zombie reserves the
                        # PID/PGID until all still-owned group work is stopped.
                        event = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                        if event is None:
                            if time.monotonic() - job_start >= args.timeout:
                                aborted = f'test-file timeout: {args.files[index]}'
                                break
                            continue
                        observed_exits[index] = event.si_status if event.si_code == os.CLD_EXITED else -event.si_status
                        completed.append(index)
                    if completed and not aborted:
                        groups = {active[index][0].pid for index in completed}
                        try:
                            running = running_groups(groups, 1)
                        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                            aborted = f'owned-group inspection: {error}'
                            break
                        for index in completed:
                            process, log, job_start, _index = active[index]
                            if process.pid in running:
                                if index not in term_deadlines:
                                    os.killpg(process.pid, signal.SIGTERM)
                                    term_deadlines[index] = time.monotonic() + args.cleanup_seconds
                                elif time.monotonic() >= term_deadlines[index]:
                                    os.killpg(process.pid, signal.SIGKILL)
                                    if time.monotonic() >= term_deadlines[index] + args.cleanup_seconds:
                                        aborted = f'owned group survived KILL: {args.files[index]}'
                                        break
                                continue
                            if index not in output_done:
                                if time.monotonic() - job_start >= args.timeout:
                                    aborted = f'test-file stdout timeout: {args.files[index]}'
                                    break
                                continue
                            code = process.wait(timeout=args.cleanup_seconds)
                            results[index] = (code, time.monotonic() - job_start)
                            failure = failure or code != 0
                            del active[index]
                            term_deadlines.pop(index, None)
                            close_output(process, log, index)
                            # Publish only after EOF, owned-group retirement and
                            # lease release. Never signal this reaped group again.
                            if shared is not None and not aborted:
                                try:
                                    publish_json(shared / f'result-{index}.json', {
                                        'id': run_id, 'index': index, 'exit': code})
                                except OSError as error:
                                    aborted = f'shared run publication failed: {error}'
                                    publication_failure_exit = next(
                                        (observed_exits[i] for i in sorted(observed_exits) if observed_exits[i] != 0), 1)
                                    break
                    if aborted:
                        break
                    if active and not read_any:
                        time.sleep(0.02)
            finally:
                stop_groups()
            for index, file in enumerate(args.files):
                result = results.get(index)
                if result is None:
                    print(f'==> test job INCOMPLETE: {file}', flush=True)
                else:
                    code, elapsed = result
                    print(f'==> test job {file} ({elapsed:.3f}s, exit {code})', flush=True)
                path = Path(directory) / f'{index}.log'
                if not path.exists():
                    continue
                with path.open('rb') as log:
                    remaining = MAX_LOG_BYTES
                    while remaining > 0 and (block := log.read(min(65536, remaining))):
                        sys.stdout.buffer.write(block)
                        remaining -= len(block)
                sys.stdout.flush()
                if index in overflowed:
                    print(f'\nOutput truncated at {MAX_LOG_BYTES} bytes: {file}', file=sys.stderr)
                if index in capture_errors:
                    print(f'Output capture incomplete: {file}: {capture_errors[index]}', file=sys.stderr)
            if aborted:
                for index in sorted(observed_exits):
                    if index not in results:
                        print(f'Completed leader: {args.files[index]} (exit {observed_exits[index]}); '
                              'group ownership cleanup required', file=sys.stderr)
                print(f'Test jobs aborted: {aborted}', file=sys.stderr)
            print(f'=== Test files: {len(results)}/{len(args.files)} completed, '
                  f'{sum(code != 0 for code, _ in results.values())} failed ===', flush=True)
    finally:
        for sig, handler in original_handlers.items():
            signal.signal(sig, handler)
    if interrupted:
        return 128 + interrupted
    if aborted:
        if publication_failure_exit is not None:
            return publication_failure_exit if publication_failure_exit > 0 else 128 - publication_failure_exit
        return 1
    if failure:
        code = next(results[index][0] for index in sorted(results) if results[index][0] != 0)
        return code if code > 0 else 128 - code
    return 0


if __name__ == '__main__':
    sys.exit(main())
