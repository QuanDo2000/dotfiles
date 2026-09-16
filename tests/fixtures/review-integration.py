"""Offline real-SDK/tool-dispatch checks. Optional argv supplies the Pi executable prefix."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
pi = sys.argv[1:] or [shutil.which("pi") or "pi"]


def run(args, cwd, env=None, logs=False):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout + (result.stderr if logs else "")


with tempfile.TemporaryDirectory(prefix="review-integration-") as directory:
    cwd = Path(directory)
    def git(*args):
        return run(["git", *args], cwd).strip()
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    (cwd / "code.txt").write_text("before\n")
    git("add", ".")
    git("commit", "-qm", "base")
    base = git("rev-parse", "HEAD")
    (cwd / "code.txt").write_text("after\n")
    git("commit", "-qam", "head")
    head = git("rev-parse", "HEAD")
    env = {**os.environ, "PI_OFFLINE": "1", "REVIEW_TEST_CWD": str(cwd),
           "REVIEW_TEST_BASE": base, "REVIEW_TEST_HEAD": head}
    command = [*pi, "--no-extensions", "--no-skills", "--no-session",
               "-e", str(repo / "tests/fixtures/review-tool.ts"),
               "--provider", "review-tool-fixture", "--model", "fixture", "--tools", "review"]
    output = run([*command, "-e", str(repo / "tests/fixtures/review-session.ts"),
                  "-p", "/test-review-session"], cwd, env, logs=True)
    assert "review-session: PASS" in output, output
    output = run([*command, "-p", "Run the review fixture twice."], cwd, env, logs=True)
    assert "review-tool: PASS" in output, output
    assert git("status", "--porcelain=v1", "--untracked-files=all") == ""
    assert git("rev-parse", "HEAD") == head
    print("review integration: PASS (SDK isolation, read tool, failure, cancellation, dispatch, reuse)")
