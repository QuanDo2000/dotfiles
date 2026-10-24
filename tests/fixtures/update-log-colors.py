"""Exercise update rendering and transcript capture without updating the host."""

import os
from pathlib import Path
import pty
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def main():
    root = Path(os.environ["TEST_HOME"]) / "color-checkout"
    scripts = root / "scripts"
    scripts.mkdir(parents=True)
    (root / "dotfile").write_bytes((ROOT / "dotfile").read_bytes())
    (scripts / "utils.sh").write_bytes((ROOT / "scripts/utils.sh").read_bytes())
    for name in ("platform", "packages", "releases", "pins", "doctor", "obsidian"):
        (scripts / f"{name}.sh").write_text(":\n")
    (scripts / "doctor.sh").write_text("doctor() { :; }\n")
    (scripts / "releases.sh").write_text(
        "_dependency_update_markers_conflict() { return 1; }\n"
        "_dependency_update_pending() { return 0; }\n"
    )
    (scripts / "packages.sh").write_text(
        "update_packages() { info 'color probe'; }\n"
    )

    for case in ("terminal", "redirected", "no-color", "dumb", "filter-error"):
        state = root / case
        env = {
            **os.environ,
            "DOTFILES_DIR": str(root),
            "DOTFILE_UPDATE_ENV": "true",
            "XDG_STATE_HOME": str(state),
            "TERM": "dumb" if case == "dumb" else "xterm-256color",
        }
        env.pop("NO_COLOR", None)
        env.pop("DOTFILE_UPDATE_LOG", None)
        if case == "no-color":
            env["NO_COLOR"] = "1"
        if case == "filter-error":
            bin_dir = root / "bin"
            bin_dir.mkdir()
            sed = bin_dir / "sed"
            sed.write_text(
                "#!/usr/bin/env bash\n"
                "while IFS= read -r line; do :; done\n"
                "printf 'log filter failed\\n' >&2\nexit 71\n"
            )
            sed.chmod(0o755)
            env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
        master, slave = pty.openpty()
        try:
            # Fixture output is under 1 KiB, so it fits the PTY before readback.
            result = subprocess.run(
                ["bash", str(root / "dotfile"), "update"],
                stdin=slave,
                stdout=subprocess.PIPE if case == "redirected" else slave,
                stderr=slave,
                env=env,
                timeout=20,
                check=False,
            )
            expected_status = 71 if case == "filter-error" else 0
            assert result.returncode == expected_status, (case, result.returncode)
            if case == "redirected":
                output = result.stdout
            else:
                os.set_blocking(master, False)
                output = os.read(master, 4096)
        finally:
            os.close(slave)
            os.close(master)
        logs = list((state / "dotfile/logs").iterdir())
        assert len(logs) == 1, (case, logs)
        if case == "filter-error":
            assert b"log filter failed" in output, output
            continue
        assert b"color probe" in output, (case, output)
        assert (b"\x1b[34mINFO\x1b[0m" in output) == (case == "terminal"), (case, output)
        transcript = logs[0].read_bytes()
        assert b"[INFO] color probe" in transcript, (case, transcript)
        assert b"\x1b" not in transcript, (case, transcript)
        assert b"exit status: 0" in transcript, (case, transcript)


if __name__ == "__main__":
    main()
