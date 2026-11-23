#!/usr/bin/env bash
# Internal profile-data worker/boundary, owned by the bounded test executor.
set -euo pipefail
if [[ "${1:-}" == --snapshot-reference ]]; then
  [[ $# == 2 ]] || exit 2
  python3 - "$@" <<'PY'
import base64
import json
import os
from pathlib import Path
import stat
import sys
from urllib.parse import urlencode


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


def prefetched_snapshot(metadata):
    # This is CmdFlakePrefetch's result, not an alias for optional metadata.path.
    if not isinstance(metadata, dict) or not {'storePath', 'hash'} <= metadata.keys():
        raise ValueError('invalid native flake prefetch schema')
    snapshot = Path(text(metadata['storePath']))
    nar_hash = text(metadata['hash'])
    if snapshot.parent != Path('/nix/store') or not snapshot.is_absolute():
        raise ValueError('invalid immutable snapshot path')
    if not nar_hash.startswith('sha256-') or len(base64.b64decode(nar_hash[7:], validate=True)) != 32:
        raise ValueError('invalid prefetched NAR digest')
    parameters = [('narHash', nar_hash)]
    # Newer clients also expose locked attributes; retain their source timestamp.
    if 'locked' in metadata:
        locked = metadata['locked']
        if not isinstance(locked, dict) or locked.get('type') != 'path':
            raise ValueError('invalid prefetched path attributes')
        if 'narHash' in locked and locked['narHash'] != nar_hash:
            raise ValueError('prefetch store/locked NAR mismatch')
        if 'lastModified' in locked:
            modified = locked['lastModified']
            if type(modified) is not int or not 0 <= modified <= 2**63 - 1:
                raise ValueError('invalid source timestamp')
            parameters.append(('lastModified', str(modified)))
    reference = 'path:' + str(snapshot) + '?' + urlencode(parameters)
    return snapshot, nar_hash, reference


def main():
    _, _, reference = prefetched_snapshot(load(Path(sys.argv[2])))
    print(json.dumps(reference))
    return 0


try:
    sys.exit(main())
except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
    print(f'Snapshot reference refused: {error}', file=sys.stderr)
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
