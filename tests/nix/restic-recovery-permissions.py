"""Native Restic/rclone recovery smoke test in disposable local storage."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(args, env, cwd, data=None, check=True):
    return subprocess.run(args, env=env, cwd=cwd, input=data, text=True,
                          capture_output=True, check=check, timeout=60)


def access(path, uid):
    acl = subprocess.run(['getfacl', '-cn', '--', str(path)], check=True,
                         capture_output=True, text=True).stdout
    entry = next((line for line in acl.splitlines() if line.startswith(f'user:{uid}:')), None)
    if entry is None:
        return None
    return entry.split('#effective:')[-1].strip() if '#effective:' in entry else entry.split(':')[2]


def main():
    helper = str(Path(sys.argv[1]).resolve())
    native = {name: shutil.which(name) for name in ('restic', 'rclone', 'setfacl', 'getfacl')}
    assert all(native.values()), native
    uid = subprocess.run(['id', '-u', 'nobody'], check=True, capture_output=True, text=True).stdout.strip()
    with tempfile.TemporaryDirectory(prefix='restic-smb-') as temporary:
        root = Path(temporary)
        home = root / 'home'
        binaries = home / '.nix-profile/bin'
        binaries.mkdir(parents=True)
        for name, executable in native.items():
            assert executable is not None
            (binaries / name).symlink_to(executable)
        config = home / '.config/rclone'
        config.mkdir(parents=True)
        (config / 'rclone.conf').write_text('[gdrive]\ntype = local\n')
        password = root / 'password'
        password.write_text('disposable-local-test-only')
        password.chmod(0o600)
        recovery = home / 'Documents/Restic Recovery'
        recovery.mkdir(parents=True)
        subprocess.run(['setfacl', '-m', f'u:{uid}:rwx,d:u:{uid}:rwx', str(recovery)], check=True)
        env = dict(os.environ, HOME=str(home), RESTIC_PASSWORD_FILE=str(password),
                   RESTIC_RECOVERY_ROOT=str(recovery), RESTIC_RECOVERY_SMB_USER='nobody',
                   RESTIC_REPOSITORY='rclone:gdrive:ServerBackup/restic',
                   RCLONE_CONFIG=str(config / 'rclone.conf'))
        source = '/mnt/storage/Storage/Documents/SMB recovery test.txt'
        payload = 'verified local native Restic restore\n'
        run([native['restic'], 'init'], env, root)
        run([native['restic'], 'backup', '--tag', 'storage-offsite', '--stdin',
             '--stdin-filename', source], env, root, data=payload)
        for _ in range(2):
            result = run(['bash', helper, 'restore', 'latest', source], env, root)
            print(result.stdout)
            line = next(line for line in result.stdout.splitlines() if line.startswith('Staged restore: '))
            target = Path(line.removeprefix('Staged restore: '))
            assert access(recovery, uid) in ('r-x', 'rwx'), 'recovery root SMB access reset'
            assert access(target, uid) == 'r-x', 'completed restore not shared read-only'
            restored = target / source.lstrip('/')
            assert restored.read_text() == payload
            assert access(restored, uid) == 'r--', 'restored file not shared read-only'
            dumped = run([native['restic'], 'dump', 'latest', source], env, root).stdout
            assert dumped == restored.read_text()
            for parent in restored.parents:
                if parent == recovery:
                    break
                assert access(parent, uid) == 'r-x', f'inaccessible restored parent: {parent}'
        before = set(recovery.iterdir())
        failure = run(['bash', helper, 'restore', 'deadbeef', source], env, root, check=False)
        assert failure.returncode != 0, 'missing snapshot should fail'
        failed = set(recovery.iterdir()) - before
        assert len(failed) == 1
        stage = failed.pop()
        assert stage.stat().st_mode & 0o077 == 0, 'failed stage is not private'
        assert access(stage, uid) in (None, '---'), 'failed stage is exposed'
        assert 'Staged restore:' not in failure.stdout
    print('PASS: repeated native restore + dump equality, read-only SMB ACL, failed restore private')


if __name__ == '__main__':
    main()
