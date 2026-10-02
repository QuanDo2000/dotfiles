"""Exercise evaluated bisync hooks on disposable files, without remote sync."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def check_access(path, expected):
    acl = run('getfacl', '-cn', '--', str(path))
    entry = next(line for line in acl.splitlines() if line.startswith('user:65534:'))
    effective = entry.split('#effective:')[-1] if '#effective:' in entry else entry.split(':')[2]
    assert effective.strip() == expected, (str(path), acl)
    assert 'other::---' in acl, (str(path), acl)


def main():
    service = json.load(sys.stdin)
    with tempfile.TemporaryDirectory(prefix='drive-acl-') as temporary:
        home = Path(temporary)
        roots = [home / 'Documents' / name for name in ('Drive', '.Drive-backup')]
        outside = home / 'outside'
        outside.write_text('untouched')
        outside.chmod(0o600)
        for root in roots:
            root.mkdir(parents=True)
            run('setfacl', '-m', 'u:65534:rwx,d:u:65534:rwx', str(root))
            (root / 'nested').mkdir()
            (root / 'plain').write_text('document')
            (root / 'program').write_text('executable')
            (root / 'program').chmod(0o700)
            (root / 'link').symlink_to(outside)
            run('chmod', '-R', 'u=rwX,go=', str(root))
        for _ in range(2):
            for field in ('ExecStartPre', 'ExecStopPost'):
                commands = service[field]
                if isinstance(commands, str):
                    commands = [commands]
                for command in commands:
                    args = shlex.split(command)
                    for index, arg in enumerate(args):
                        for root in roots:
                            if arg.endswith('/Documents/' + root.name):
                                args[index] = str(root)
                    run(*args)
                for root in roots:
                    check_access(root, 'rwx')
                if field == 'ExecStopPost':
                    for root in roots:
                        check_access(root / 'nested', 'rwx')
                        check_access(root / 'plain', 'rw-')
                        check_access(root / 'program', 'rwx')
            # Simulate a new private file downloaded by the UMask=0077 service.
            for root in roots:
                new = root / 'plain'
                new.chmod(0o600)
        assert outside.stat().st_mode & 0o777 == 0o600
        assert outside.read_text() == 'untouched'
    print('bisync hooks: SMB ACL retained, other denied, executable preserved, symlink target untouched')


if __name__ == '__main__':
    main()
