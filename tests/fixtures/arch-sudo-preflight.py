"""Exercise the sudo preflight with terminal FDs, without invoking real sudo."""

import os
from pathlib import Path
import pty
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = r'''
set -euo pipefail
source "$1/scripts/packages.sh"
DRY=false
info() { printf '%s\n' "$*" >&2; }
fail() { printf '%s\n' "$*" >&2; exit 1; }
sudo() {
  printf '%s\n' "$*" >> "$CALLS"
  case "$*" in
    '-n -v') return 1 ;;
    '-v') [[ "$AUTH_RESULT" == success ]] ;;
    *) return 99 ;;
  esac
}
_preflight_arch_service_state_backup
printf 'continued\n' >> "$CALLS"
'''


def main():
    # Both successful authentication and cancellation must use sudo's prompt;
    # cancellation must not let the caller proceed toward activation.
    for result in ("success", "cancelled"):
        calls = Path(os.environ["TEST_TMPDIR"]) / f"sudo-{result}.log"
        master, slave = pty.openpty()
        try:
            process = subprocess.run(
                ["bash", "-c", SCRIPT, "preflight", str(ROOT)],
                stdin=slave,
                stdout=subprocess.DEVNULL,
                stderr=slave,
                env={**os.environ, "CALLS": str(calls), "AUTH_RESULT": result},
                timeout=10,
                check=False,
            )
        finally:
            os.close(slave)
            os.close(master)
        expected_calls = ["-n -v", "-v"]
        if result == "success":
            expected_calls.append("continued")
        assert calls.read_text().splitlines() == expected_calls, calls.read_text()
        assert process.returncode == (0 if result == "success" else 1)


if __name__ == "__main__":
    main()
