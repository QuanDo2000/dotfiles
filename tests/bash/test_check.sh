#!/usr/bin/env bash
# Local verification entrypoint coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

# Substitute expensive tool boundaries, but execute the real gate and re-exec.
_check_fixture() {
  export CHECK_ROOT="$TEST_TMPDIR/check" CHECK_CALLS="$TEST_TMPDIR/check-calls"
  mkdir -p "$CHECK_ROOT/scripts" "$CHECK_ROOT/tests/bash" "$CHECK_ROOT/bin"
  cp "$REPO_DIR/scripts/check.sh" "$CHECK_ROOT/scripts/check.sh"
  cp "$REPO_DIR/scripts/test_jobs.py" "$CHECK_ROOT/scripts/test_jobs.py"
  cp "$REPO_DIR/scripts/check_nix.sh" "$REPO_DIR/scripts/check_powershell.sh" "$REPO_DIR/scripts/check_profile.sh" "$CHECK_ROOT/scripts/"
  local stage
  for stage in check_bash check_lint; do
    [[ ! -f "$REPO_DIR/scripts/$stage.sh" ]] || cp "$REPO_DIR/scripts/$stage.sh" "$CHECK_ROOT/scripts/"
  done
  touch "$CHECK_ROOT/dotfile" "$CHECK_ROOT/tests/bash/test_fixture.sh"
  : > "$CHECK_CALLS"
  cat > "$CHECK_ROOT/tests/bash/runner.sh" <<'SH'
printf 'bash-tests\n' >> "$CHECK_CALLS"
if [[ "${CHECK_SYNC:-0}" == 1 ]]; then
  deadline=$((SECONDS + 3))
  while [[ ! -f "$CHECK_ROOT/nix-started" ]]; do
    (( SECONDS < deadline )) || exit 91
    sleep 0.01
  done
fi
exit "${CHECK_TEST_EXIT:-0}"
SH
  cat > "$CHECK_ROOT/bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$CHECK_CALLS"
if [[ "$1" == develop ]]; then
  shift 3
  exec "$@"
fi
if [[ "$1" == flake && "${CHECK_SYNC:-0}" == 1 ]]; then touch "$CHECK_ROOT/nix-started"; fi
[[ "$1" != "${CHECK_FAIL:-}" ]] || exit 42
if [[ "$1" == eval && "$*" == *username* ]]; then printf 'test-user'; fi
if [[ "$1" == build ]]; then printf '/fixture-package\n'; fi
SH
  local tool
  printf '#!/usr/bin/env bash\nprintf "pwsh %%s\\n" "$*" >> "$CHECK_CALLS"\nexit "${CHECK_POWERSHELL_EXIT:-0}"\n' > "$CHECK_ROOT/bin/pwsh"
  printf '#!/usr/bin/env bash\nprintf "shellcheck %%s\\n" "$*" >> "$CHECK_CALLS"\nexit "${CHECK_LINT_EXIT:-0}"\n' > "$CHECK_ROOT/bin/shellcheck"
  printf '#!/usr/bin/env bash\nif [[ "$1" == */test_jobs.py || ( "$1" == - && "${2:-}" == --platform-observations ) ]]; then exec %q "$@"; fi\nprintf "python3 %%s\\n" "$*" >> "$CHECK_CALLS"\n' "$(type -P python3)" > "$CHECK_ROOT/bin/python3"
  chmod +x "$CHECK_ROOT/bin/"*
}

test_check_script_runs_repo_verification() {
  _check_fixture
  assert_exit_code 0 env -u DOTFILE_CHECK_IN_DEV_SHELL PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  local calls
  calls="$(<"$CHECK_CALLS")"
  assert_contains "$calls" "nix develop path:$CHECK_ROOT -c"
  assert_contains "$calls" 'bash-tests'
  assert_contains "$calls" 'pwsh '
  assert_contains "$calls" "nix flake check path:$CHECK_ROOT --no-build --all-systems"
  assert_contains "$calls" "path:$CHECK_ROOT#pi-extensions"
  if [[ "$(uname -s)" == Linux ]]; then
    assert_contains "$calls" 'test-user@linux'
    assert_contains "$calls" 'test-user@arch-server'
    assert_contains "$calls" "path:$CHECK_ROOT#pi-agent"
    assert_contains "$calls" "path:$CHECK_ROOT#rex"
    assert_contains "$calls" 'python3 '
    assert_equals 1 "$(grep -c '^nix build .*#hyprsunset-status' "$CHECK_CALLS")"
  else
    assert_contains "$calls" 'darwinConfigurations.mac.system.drvPath'
  fi
  assert_contains "$calls" 'shellcheck '
  local lint_files lint_file
  lint_files="$(cd "$CHECK_ROOT" && printf '%s\n' dotfile scripts/*.sh tests/bash/*.sh)" || return
  while IFS= read -r lint_file; do
    assert_equals 1 "$(grep -Fxc "shellcheck -S warning -e SC1090,SC1091,SC2034,SC2088,SC2120 $lint_file" "$CHECK_CALLS")"
  done <<< "$lint_files"

  # A source-independent Nix stage must start before the blocked Bash stage
  # finishes. The old Bash-before-post barrier times out with 91 here.
  assert_exit_code 0 env -u DOTFILE_CHECK_IN_DEV_SHELL CHECK_SYNC=1 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_file_exists "$CHECK_ROOT/nix-started"
}

test_check_script_preserves_failed_tests_and_build() {
  _check_fixture
  # A present producer source that exits without publishing must not block
  # admission forever or suppress the independent native flake command.
  touch "$CHECK_ROOT/tests/bash/test_home_profiles.sh"
  assert_exit_code 23 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_TEST_EXIT=23 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'nix flake check'
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '
  : > "$CHECK_CALLS"
  assert_exit_code 42 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_FAIL=build PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '
  : > "$CHECK_CALLS"
  assert_exit_code 42 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_FAIL=flake PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'nix build'
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '
}

test_check_script_collects_all_stage_failures() {
  _check_fixture
  assert_exit_code 37 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_POWERSHELL_EXIT=37 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'nix flake check'
  assert_contains "$(<"$CHECK_CALLS")" 'nix build'
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '

  : > "$CHECK_CALLS"
  assert_exit_code 37 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_POWERSHELL_EXIT=37 CHECK_FAIL=build PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'pwsh '
  assert_contains "$(<"$CHECK_CALLS")" 'nix build'
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '

  : > "$CHECK_CALLS"
  assert_exit_code 19 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_LINT_EXIT=19 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'bash-tests'
  assert_contains "$(<"$CHECK_CALLS")" 'nix build'
  : > "$CHECK_CALLS"
  assert_exit_code 23 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_TEST_EXIT=23 CHECK_POWERSHELL_EXIT=37 CHECK_FAIL=build CHECK_LINT_EXIT=19 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_contains "$(<"$CHECK_CALLS")" 'pwsh '
  assert_contains "$(<"$CHECK_CALLS")" 'shellcheck '
}

test_profile_worker_transfers_bounded_pure_expression() {
  REPO_DIR="$REPO_DIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import json
import os
from pathlib import Path
import subprocess
import tempfile

worker = Path(os.environ['REPO_DIR']) / 'scripts/check_profile.sh'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    binary = root / 'bin'
    binary.mkdir()
    calls = root / 'argv.json'
    mock = binary / 'nix'
    mock.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['PROFILE_ARGV'], 'w') as output:
    json.dump(sys.argv[1:], output)
print('{"worker":true}')
sys.exit(int(os.environ.get('PROFILE_EXIT', '0')))
''')
    mock.chmod(0o755)
    source = root / 'projection.nix'
    env = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
           'PROFILE_ARGV': str(calls), 'PROFILE_EXIT': '0'}
    for payload in ('{ sample = "λ"; }\n\n'.encode(), b'"' + b'a' * 16381 + b'"\n'):
        source.write_bytes(payload)
        result = subprocess.run(['bash', str(worker), str(source)], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 0, result.stderr
        arguments = json.loads(calls.read_text())
        assert arguments[:-1] == ['eval', '--option', 'pure-eval', 'true', '--json', '--expr'], arguments[:-1]
        assert arguments[-1].encode('utf-8') == payload
        assert json.loads(source.with_suffix('.json').read_text()) == {'worker': True}
    for payload, reason in ((b'"\xff"', b'utf-8'), (b'"\0"', b'NUL'),
                            (b'"' + b'a' * 16383 + b'"', b'16KiB')):
        calls.unlink(missing_ok=True)
        source.write_bytes(payload)
        result = subprocess.run(['bash', str(worker), str(source)], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 125 and reason in result.stderr, result.stderr
        assert not calls.exists(), 'refused input reached Nix'
        assert source.with_suffix('.json').read_bytes() == b''
    source.write_text('{}')
    result = subprocess.run(['bash', str(worker), str(source)], env={**env, 'PROFILE_EXIT': '42'},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 42, result.stderr
PY
}

test_bash_runner_accepts_multiple_test_files() {
  local fixtures="$TEST_TMPDIR/fixtures" output
  mkdir -p "$fixtures"
  printf 'test_one() { :; }\n' > "$fixtures/test_one.sh"
  printf 'test_two() { :; }\n' > "$fixtures/test_two.sh"

  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_one.sh" "$fixtures/test_two.sh" 2>&1)"

  assert_contains "$output" "--- test_one.sh ---"
  assert_contains "$output" "--- test_two.sh ---"
}

test_bash_runner_discovers_tests_without_compgen_and_fails_empty_files() {
  local bash_env="$TEST_TMPDIR/bash-env" fixture="$TEST_TMPDIR/test_fixture.sh" output status=0
  printf 'enable -n compgen 2>/dev/null || true\n' > "$bash_env"
  printf 'test_body() { :; }\n' > "$fixture"

  output="$(BASH_ENV="$bash_env" bash "$REPO_DIR/tests/bash/runner.sh" "$fixture" 2>&1)" || status=$?
  assert_equals 0 "$status"
  assert_contains "$output" '1 passed, 0 failed, 1 total'

  status=0
  : > "$fixture"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixture" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  no test_* functions found'
}

test_bash_runner_fails_setup_and_teardown_errors() {
  local fixtures="$TEST_TMPDIR/fixtures" output status=0
  mkdir -p "$fixtures"
  printf 'setup() { false; :; }\nteardown() { :; }\ntest_body() { :; }\n' > "$fixtures/test_setup.sh"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_setup.sh" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  test_body'

  status=0
  printf 'teardown() { return 43; }\ntest_body() { :; }\n' > "$fixtures/test_teardown.sh"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_teardown.sh" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  test_body'
}

test_parallel_file_jobs_bound_workers_collect_failures_and_cancel() {
  REPO_DIR="$REPO_DIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

repo = Path(os.environ['REPO_DIR'])
helper = [sys.executable, str(repo / 'scripts/test_jobs.py')]
runner = ['bash', str(repo / 'tests/bash/runner.sh')]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    events = root / 'events'
    files = []
    for index in range(4):
        file = root / f'test_{index}.sh'
        file.write_text(f'''test_body() {{
  [[ "$PSModuleAnalysisCachePath" == "$TMPDIR/ps-module-cache" ]] || return 99
  printf 'start {index}\\n' >> '{events}'
  sleep 0.15
  printf 'end {index}\\n' >> '{events}'
  {'false' if index == 1 else ':'}
}}
''')
        files.append(str(file))
    result = subprocess.run([*helper, '--jobs', '2', '--timeout', '5', '--files', *files, '--', *runner],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode == 1, result.stdout + result.stderr
    assert '4/4 completed, 1 failed' in result.stdout, result.stdout
    active = peak = 0
    for event in events.read_text().splitlines():
        active += 1 if event.startswith('start') else -1
        peak = max(peak, active)
        assert 0 <= active <= 2
    assert peak == 2 and active == 0
    assert len(events.read_text().splitlines()) == 8

    # Priority changes launch order only: do not omit/repeat files, reorder
    # reports, or return a later file's failure just because it started first.
    events.unlink()
    early = root / 'early.sh'
    late = root / 'late.sh'
    early.write_text(f"printf 'early\\n' >> '{events}'; exit 21\n")
    late.write_text(f"printf 'late\\n' >> '{events}'; exit 37\n")
    prioritized = [*helper, '--jobs', '2', '--timeout', '5', '--first', str(late),
                   '--files', str(early), str(late), '--', 'bash']
    result = subprocess.run(prioritized, capture_output=True, text=True, timeout=15)
    assert result.returncode == 21, result.stdout + result.stderr
    assert '2/2 completed, 2 failed' in result.stdout
    assert sorted(events.read_text().splitlines()) == ['early', 'late']
    assert result.stdout.index(str(early)) < result.stdout.index(str(late))
    for first in ((str(root / 'unknown.sh'),), (str(late), str(late))):
        options = [arg for file in first for arg in ('--first', file)]
        result = subprocess.run([*helper, *options, '--files', str(early), str(late), '--', 'bash'],
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 2 and '--first' in result.stderr
        assert sorted(events.read_text().splitlines()) == ['early', 'late']

    child_file = root / 'child'
    slow = root / 'test_slow.sh'
    slow.write_text(f'test_body() {{ sleep 30 & printf "%s\\n" "$!" > "{child_file}"; wait "$!"; }}\n')
    for mode in ('file-timeout', 'total-timeout', 'cancel'):
        cancel = mode == 'cancel'
        child_file.unlink(missing_ok=True)
        limits = ['--timeout', '0.3'] if mode == 'file-timeout' else ['--timeout', '5']
        if mode == 'total-timeout':
            limits += ['--total-timeout', '0.3']
        process = subprocess.Popen([*helper, '--jobs', '2', *limits,
                                    '--files', str(slow), '--', *runner],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            if cancel:
                deadline = time.monotonic() + 3
                while not child_file.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert child_file.exists(), 'worker did not start'
                process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=10)
            assert process.returncode == (143 if cancel else 1), stdout + stderr
            reason = {'file-timeout': 'test-file timeout', 'total-timeout': 'overall test-job deadline',
                      'cancel': 'interrupted'}[mode]
            assert reason in stderr, stderr
            child = int(child_file.read_text())
            state = subprocess.run(['ps', '-p', str(child), '-o', 'stat='],
                                   capture_output=True, text=True, timeout=3).stdout.strip()
            assert not state or state.startswith('Z'), f'worker descendant still running: {child} {state}'
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=10)

    # The outer leader exits on TERM before its nested coordinator. The latter
    # must retain its grace to kill a TERM-ignoring, separately grouped leaf.
    child_file.unlink(missing_ok=True)
    leaf = root / 'leaf.py'
    leaf.write_text('import os,pathlib,signal,time\n'
                    'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                    f'pathlib.Path({str(child_file)!r}).write_text(str(os.getpid()))\n'
                    'time.sleep(30)\n')
    parent = root / 'parent.py'
    parent.write_text('import subprocess,sys\n'
                      f'sys.exit(subprocess.call({[*helper, "--cleanup-seconds", "0.1", "--timeout", "5", "--files", str(leaf), "--", sys.executable]!r}))\n')
    process = subprocess.Popen([*helper, '--cleanup-seconds', '0.5', '--timeout', '5',
                                '--files', str(parent), '--', sys.executable],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 3
        while not child_file.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert child_file.exists(), 'nested worker did not start'
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == 143, stdout + stderr
        child = int(child_file.read_text())
        state = subprocess.run(['ps', '-p', str(child), '-o', 'stat='],
                               capture_output=True, text=True, timeout=3).stdout.strip()
        assert not state or state.startswith('Z'), f'nested leaf survived: {child} {state}'
    finally:
        if process.poll() is None:
            process.terminate()
            process.communicate(timeout=5)
        if child_file.exists():
            child = int(child_file.read_text())
            command = subprocess.run(['ps', '-p', str(child), '-o', 'command='],
                                     capture_output=True, text=True, timeout=3).stdout.strip()
            if command == f'{sys.executable} {leaf}':
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    # Normal zero/nonzero leader exit must retain the group lease until its
    # surviving work is stopped; neither case may discard scratch underneath it.
    release = root / 'release'
    retired_leaf = root / 'retired_leaf.py'
    retired_leaf.write_text('import os,pathlib,signal,time\n'
                            'signal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
                            f'p=pathlib.Path({str(child_file)!r}); t=p.with_suffix(".tmp")\n'
                            't.write_text(str(os.getpid())); t.replace(p)\n'
                            'time.sleep(30)\n')
    for code in (0, 17):
        child_file.unlink(missing_ok=True)
        release.unlink(missing_ok=True)
        parent.write_text('import pathlib,subprocess,sys,time\n'
                          f'subprocess.Popen([sys.executable,{str(retired_leaf)!r}])\n'
                          f'while not pathlib.Path({str(release)!r}).exists(): time.sleep(.01)\n'
                          f'sys.exit({code})\n')
        process = subprocess.Popen([*helper, '--cleanup-seconds', '0.1', '--timeout', '5',
                                    '--files', str(parent), '--', sys.executable],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        lease = None
        try:
            deadline = time.monotonic() + 3
            while not child_file.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            child = int(child_file.read_text())
            group = os.getpgid(child)
            lease = subprocess.run(['ps', '-p', str(child), '-o', 'lstart=,command='],
                                   capture_output=True, text=True, timeout=3).stdout.strip()
            assert lease.endswith(f'{sys.executable} {retired_leaf}')
            release.touch()
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == code, stdout + stderr
            state = subprocess.run(['ps', '-p', str(child), '-o', 'stat='],
                                   capture_output=True, text=True, timeout=3).stdout.strip()
            assert not state or state.startswith('Z'), f'retired owned group survived: {child}'
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)
            if lease:
                current = subprocess.run(['ps', '-p', str(child), '-o', 'lstart=,command='],
                                         capture_output=True, text=True, timeout=3).stdout.strip()
                try:
                    if current == lease and os.getpgid(child) == group:
                        os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
PY
}

test_parallel_file_jobs_bound_spool_and_preserve_output_eof() {
  REPO_DIR="$REPO_DIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

helper = [sys.executable, str(Path(os.environ['REPO_DIR']) / 'scripts/test_jobs.py')]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    worker = root / 'output.py'
    payload = b'\x00\xff\nabc' * 350000
    worker.write_text('import os,sys,time\n'
                      'sys.stdout.buffer.write(b"BEGIN_PAYLOAD\\n" + b"\\x00\\xff\\nabc"*350000 + b"\\nEND_PAYLOAD\\n");sys.stdout.flush()\n'
                      'sys.stderr.write("MERGED_STDERR\\n");sys.stderr.flush()\n'
                      'os.close(1);os.close(2);time.sleep(.03)\n'
                      'sys.exit(int(os.environ["OUTPUT_TEST_EXIT"]))\n')
    for code in (0, 17):
        result = subprocess.run([*helper, '--timeout', '5', '--files', str(worker), '--',
                                 sys.executable], env={**os.environ, 'OUTPUT_TEST_EXIT': str(code)},
                                capture_output=True, timeout=10)
        assert result.returncode == code, f'output worker exit {result.returncode}'
        body = result.stdout.split(b'BEGIN_PAYLOAD\n', 1)[1].split(b'\nEND_PAYLOAD\n', 1)[0]
        assert body == payload, 'binary output was lost or corrupted'
        assert b'MERGED_STDERR\n' in result.stdout
        assert b'1/1 completed' in result.stdout

    record = root / 'spool'
    worker.write_text('import os,pathlib,signal,time\n'
                      'signal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
                      f'p=pathlib.Path({str(record)!r});t=p.with_suffix(".tmp")\n'
                      't.write_text(str(pathlib.Path(os.environ["TMPDIR"]).parent/"0.log"));t.replace(p)\n'
                      'for _ in range(288): os.write(1,b"x"*65536)\n'
                      'time.sleep(2)\n')
    raw = root / 'captured'
    peak = 0
    with raw.open('wb') as output:
        process = subprocess.Popen([*helper, '--cleanup-seconds', '.1', '--timeout', '3',
                                    '--files', str(worker), '--', sys.executable],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 6
            while process.poll() is None:
                if record.exists():
                    try: peak = max(peak, Path(record.read_text()).stat().st_size)
                    except FileNotFoundError: pass
                assert time.monotonic() < deadline, 'output-bound watchdog expired'
                time.sleep(.002)
            assert process.wait(timeout=1) == 1
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
    assert 0 < peak <= 16*1024*1024, f'private spool exceeded bound: {peak}'
    with raw.open('rb') as output:
        output.seek(max(0, raw.stat().st_size - 4096))
        tail = output.read()
    assert b'output limit exceeded' in tail and b'Output truncated at' in tail
PY
}

test_bash_runner_uses_repo_working_directory() {
  local output status=0
  output="$(cd / && bash "$REPO_DIR/tests/bash/runner.sh" test_codex_status.sh 2>&1)" || status=$?
  assert_equals 0 "$status"
  assert_contains "$output" '0 failed'
}

test_profile_fixture_requires_materialized_snapshot_before_workers() {
  REPO_DIR="$REPO_DIR" METADATA_TEST_TMPDIR="$TEST_TMPDIR" python3 - <<'PY' 2>>"$ERROR_FILE"
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(os.environ['REPO_DIR'])
with tempfile.TemporaryDirectory(dir=os.environ['METADATA_TEST_TMPDIR']) as directory:
    root = Path(directory)
    binary = root / 'bin'
    binary.mkdir()
    native = binary / 'nix'
    native.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['SNAPSHOT_CALLS'], 'a') as output:
    output.write(json.dumps(args) + "\\n")
digest = 'sha256-' + 'A'*43 + '='
store = '/nix/store/' + '0'*32 + '-source'
origin = {'type': 'path', 'path': os.environ['REPO_DIR']}
if args[:2] == ['flake', 'metadata']:
    # Selected Determinate CmdFlakeMetadata may omit path and return an
    # attempted, not necessarily locked, URL. Do not invent storePath here.
    metadata = {'url': 'path:' + os.environ['REPO_DIR'], 'original': origin, 'locked': origin}
    if os.environ['SNAPSHOT_MODE'] == 'legacy':
        metadata.update(path=store, url='path:/fixture?lastModified=42&narHash=sha256-' + 'A'*43 + '%3D')
    print(json.dumps(metadata))
    raise SystemExit(0)
if args[:2] == ['flake', 'prefetch']:
    # CmdFlakePrefetch explicitly fetches to the store and queries its NAR hash.
    print(json.dumps({'storePath': store, 'hash': digest if os.environ['SNAPSHOT_MODE'] != 'malformed' else 'invalid',
                      'original': origin, 'locked': {**origin, 'narHash': digest, 'lastModified': 42}}))
    raise SystemExit(0)
# Deliberately fail only the mock evaluator: this check owns metadata admission,
# not a fake Home DTO. The real supervisor still retires every admitted worker.
raise SystemExit(42)
''')
    native.chmod(0o755)
    owner = root / 'owner.sh'
    owner.write_text('set -euo pipefail\nunset -f nix 2>/dev/null || true\n'
                     'source "$REPO_DIR/tests/bash/test_home_profiles.sh"\n_profile_fixture\n')
    for mode in ('lazy', 'legacy', 'malformed'):
        calls_file = root / (mode + '.jsonl')
        environment = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
                       'SNAPSHOT_MODE': mode, 'SNAPSHOT_CALLS': str(calls_file)}
        for name in ('TEST_JOBS_SHARED_DIR', 'TEST_JOBS_SHARED_ROLE'):
            environment.pop(name, None)
        result = subprocess.run([sys.executable, str(repo / 'scripts/test_jobs.py'),
                                 '--jobs', '1', '--timeout', '10', '--total-timeout', '12',
                                 '--cleanup-seconds', '1', '--files', str(owner), '--', 'bash'],
                                env=environment, capture_output=True, timeout=18)
        assert result.returncode != 0, 'intentional mock failure was lost'
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()]
        snapshots = [args for args in calls if args[:2] == ['flake', 'prefetch']]
        evaluations = [args for args in calls if args[:1] == ['eval']]
        if mode == 'malformed':
            assert not evaluations, 'incomplete snapshot reached pure workers'
        else:
            from urllib.parse import parse_qs
            assert len(evaluations) == 4, (mode, len(evaluations))
            for args in evaluations:
                assert 'true' == args[args.index('pure-eval') + 1]
                expression = args[args.index('--expr') + 1]
                reference, _ = json.JSONDecoder().raw_decode(expression.split('builtins.getFlake ', 1)[1])
                path, _, query = reference.partition('?')
                assert path == 'path:/nix/store/' + '0'*32 + '-source', (mode, reference)
                assert parse_qs(query) == {'narHash': ['sha256-' + 'A'*43 + '='], 'lastModified': ['42']}
        assert len(snapshots) == 1 and not any(args[:2] == ['flake', 'metadata'] for args in calls), calls
PY
}
