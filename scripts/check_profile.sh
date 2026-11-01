#!/usr/bin/env bash
# Internal profile-data worker/boundary, owned by the bounded test executor.
set -euo pipefail
if [[ "${1:-}" == --platform-observations ]]; then
  [[ ( $# == 3 && "$2" == probe ) || ( $# == 4 && ( "$2" == publish || "$2" == read ) ) ]] || exit 2
  python3 - "$@" <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import time
from urllib.parse import parse_qs


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def load(path, limit=16384):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('record is not a regular file')
        raw = source.read(limit + 1)
    if len(raw) > limit:
        raise ValueError('record size ceiling exceeded')
    return json.loads(raw, object_pairs_hook=unique_object)


def text(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 4096 or any(c in value for c in '\0\r\n'):
        raise ValueError('invalid bounded text field')
    return value


def digest(path):
    with path.open('rb') as source:
        data = source.read(1048577)
    if len(data) > 1048576:
        raise ValueError('source identity file exceeds 1MiB')
    return hashlib.sha256(data).hexdigest()


def main():
    action = sys.argv[2]
    role = '2' if action == 'read' else '0'
    shared_value = os.environ.get('TEST_JOBS_SHARED_DIR')
    if not shared_value or os.environ.get('TEST_JOBS_SHARED_ROLE') != role:
        return 3  # Unavailable: keep the original independent native path.
    repo = Path(sys.argv[3]).resolve()
    if not (repo / 'tests/bash/test_home_profiles.sh').is_file():
        return 3  # Disposable gate fixtures need not have a Home producer.
    shared = Path(shared_value)
    header = load(shared / 'manifest.json')
    expected_files = [str(repo / 'scripts' / name) for name in (
        'check_bash.sh', 'check_powershell.sh', 'check_nix.sh', 'check_lint.sh')]
    if (not isinstance(header, dict) or set(header) != {'protocol', 'id', 'pid', 'files'}
            or header['protocol'] != 'test-jobs-run-v1' or header['id'] != shared.parent.name
            or header['files'] != expected_files or type(header['pid']) is not int or header['pid'] <= 1):
        raise ValueError('invalid shared-run binding')
    pid = os.getpid()
    for _ in range(16):
        if pid == header['pid']:
            break
        if pid <= 1:
            raise ValueError('shared owner is not an ancestor')
        fields = Path(f'/proc/{pid}/stat').read_text().rpartition(') ')[2].split()
        pid = int(fields[1])
    else:
        raise ValueError('shared owner ancestry ceiling exceeded')
    if action == 'probe':
        return 0

    def validate(record):
        keys = {'protocol', 'id', 'origin', 'snapshot', 'narHash', 'flakeRef',
                'lockSha256', 'hostSha256', 'username', 'targets'}
        if not isinstance(record, dict) or set(record) != keys:
            raise ValueError('invalid observation schema')
        if (record['protocol'] != 'native-platform-observations-v1'
                or record['id'] != header['id'] or record['origin'] != str(repo)):
            raise ValueError('observation run/source mismatch')
        for key in keys - {'targets'}:
            text(record[key])
        if (not record['narHash'].startswith('sha256-')
                or len(base64.b64decode(record['narHash'][7:], validate=True)) != 32):
            raise ValueError('invalid NAR digest')
        snapshot = Path(record['snapshot'])
        if snapshot.parent != Path('/nix/store'):
            raise ValueError('invalid immutable snapshot path')
        if (not record['flakeRef'].startswith(f'path:{snapshot}?')
                or parse_qs(record['flakeRef'].partition('?')[2]).get('narHash') != [record['narHash']]):
            raise ValueError('immutable reference/NAR mismatch')
        targets = record['targets']
        if not isinstance(targets, dict) or set(targets) != {'linux', 'arch-server'}:
            raise ValueError('invalid target roles')
        for value in targets.values():
            value = text(value)
            if not value.startswith('/nix/store/') or not value.endswith('.drv'):
                raise ValueError('invalid native drv observation')
        for key in ('lockSha256', 'hostSha256'):
            if len(record[key]) != 64 or any(c not in '0123456789abcdef' for c in record[key]):
                raise ValueError('invalid source digest')

    destination = shared / 'platform-observations.json'
    if action == 'publish':
        ready = Path(sys.argv[4])
        metadata = load(ready / 'metadata.json', 1048576)
        reference = load(ready / 'flake-ref.json')
        # debt: private fixture JSON <=64MiB; raise/revalidate before real data reaches it.
        fixture = load(ready / 'fixture.json', 64 * 1024 * 1024)
        observations = fixture['platformDrvPaths']
        if not isinstance(observations, dict) or set(observations) != {'username', 'linux', 'arch-server'}:
            raise ValueError('incomplete native platform observations')
        snapshot = Path(text(metadata['path']))
        if snapshot.parent != Path('/nix/store'):
            raise ValueError('invalid producer snapshot')
        expected_reference = 'path:' + str(snapshot) + '?' + metadata['url'].split('?', 1)[1]
        if reference != expected_reference:
            raise ValueError('producer reference mismatch')
        record = {'protocol': 'native-platform-observations-v1', 'id': header['id'], 'origin': str(repo),
                  'snapshot': str(snapshot), 'narHash': metadata['locked']['narHash'], 'flakeRef': reference,
                  'lockSha256': digest(snapshot / 'flake.lock'), 'hostSha256': digest(snapshot / 'config/host.nix'),
                  'username': observations['username'],
                  'targets': {key: observations[key] for key in ('linux', 'arch-server')}}
        validate(record)
        payload = (json.dumps(record, separators=(',', ':')) + '\n').encode()
        if len(payload) > 16384:
            raise ValueError('observation record exceeds 16KiB')
        pending = shared / f'platform-{os.getpid()}.pending'
        with pending.open('xb') as output:
            if output.write(payload) != len(payload):
                raise OSError('short observation write')
        # Exclusive publication: never overwrite a duplicate/stale record.
        os.link(pending, destination)
        pending.unlink()
        return 0

    # debt: wait <=303s (Home file300 + owner3); revalidate if either owner budget changes.
    deadline = time.monotonic() + 303
    while True:
        try:
            record = load(destination)
            break
        except FileNotFoundError:
            try:
                result = load(shared / 'result-0.json')
            except FileNotFoundError:
                if time.monotonic() >= deadline:
                    return 3
                time.sleep(.02)
                continue
            if (not isinstance(result, dict) or set(result) != {'id', 'index', 'exit'}
                    or result['id'] != header['id'] or type(result['index']) is not int
                    or result['index'] != 0 or type(result['exit']) is not int):
                raise ValueError('invalid producer completion')
            return 3
    validate(record)
    if (record['username'] != sys.argv[4] or record['lockSha256'] != digest(repo / 'flake.lock')
            or record['hostSha256'] != digest(repo / 'config/host.nix')):
        raise ValueError('observation input identity mismatch')
    print(f"\n==> native platform drv observations (fresh shared snapshot {record['snapshot']})")
    print(record['targets']['linux'])
    print(record['targets']['arch-server'])
    print('NATIVE_PLATFORM_OBSERVATIONS_FRESH=1')
    return 0


try:
    sys.exit(main())
except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
    print(f'Platform observations refused: {error}', file=sys.stderr)
    sys.exit(125)
PY
  exit "$?"
fi
[[ $# == 1 && "$1" == *.nix && -f "$1" ]] || exit 2
python3 - "$1" <<'PY' > "${1%.nix}.json"
import os
import sys

try:
    # debt: expressions are at most 16KiB; revisit only when a producer needs more.
    with open(sys.argv[1], 'rb') as source:
        expression = source.read(16385)
    if len(expression) > 16384:
        raise ValueError('expression exceeds 16KiB')
    if b'\0' in expression:
        raise ValueError('expression contains NUL')
    expression.decode('utf-8')  # Validate, but pass the original bytes without locale conversion.
    os.execvp(b'nix', [b'nix', b'eval', b'--option', b'pure-eval', b'true',
                      b'--json', b'--expr', expression])
except (OSError, ValueError) as error:
    print(f'Profile expression refused: {error}', file=sys.stderr)
    sys.exit(125)
PY
