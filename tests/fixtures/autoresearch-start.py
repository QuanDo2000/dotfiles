"""Exercise real Pi tool dispatch/session replacement, with an offline model only."""
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading

base, extension, fixture = map(Path, sys.argv[1:])
goal = "reduce latency; six iterations, correctness checks and 250k-cell frame times"


def run(*args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


for kind, scenario in [("git", "clean"), ("jj", "clean"), ("git", "dirty"), ("jj", "dirty"), ("git", "cancel")]:
    directory = base / f"{kind}-{scenario}"
    directory.mkdir()
    root = directory / "repo"
    if kind == "git":
        run("git", "init", "-q", str(root), cwd=directory)
        run("git", "config", "user.name", "Test", cwd=root)
        run("git", "config", "user.email", "test@example.invalid", cwd=root)
        run("git", "config", "commit.gpgsign", "false", cwd=root)
    else:
        run("jj", "git", "init", str(root), cwd=directory)
        run("jj", "config", "set", "--repo", "user.name", "Test", cwd=root)
        run("jj", "config", "set", "--repo", "user.email", "test@example.invalid", cwd=root)
    (root / "input").write_text("baseline\n")
    if kind == "git":
        run("git", "add", "input", cwd=root)
        run("git", "commit", "-qm", "baseline", cwd=root)
    else:
        run("jj", "commit", "-m", "baseline", cwd=root)
    if scenario == "dirty":
        (root / "dirty").write_text("preserve\n")
    process = subprocess.Popen(
        ["pi", "--mode", "rpc", "--no-extensions", "-e", str(extension), "-e", str(fixture),
         "--provider", "autoresearch-test", "--model", "fixture"],
        cwd=root, env={**os.environ, "PI_OFFLINE": "1", "TEST_GOAL": goal,
                       "TEST_CANCEL": "1" if scenario == "cancel" else "0"},
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    events = queue.Queue()
    seen = []

    def collect():
        for line in process.stdout:
            events.put(json.loads(line))

    threading.Thread(target=collect, daemon=True).start()

    def send(message):
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def until(predicate):
        while True:
            try:
                event = events.get(timeout=20)
            except queue.Empty:
                raise AssertionError(f"{kind}/{scenario}: missing event; recent: {seen[-8:]}") from None
            seen.append(event)
            if predicate(event):
                return event

    def command(name):
        send({"id": name, "type": "prompt", "message": "/" + name})

    def probe():
        command("test-probe")
        event = until(lambda e: e.get("type") == "extension_ui_request" and '"probe":true' in e.get("message", ""))
        return json.loads(event["message"])

    try:
        before = probe()
        assert "autoresearch_start" in before["active"], "startup tool is not discoverable while mode is off"
        assert "autoresearch_run" not in before["active"]
        command("test-reload")
        until(lambda e: e.get("id") == "test-reload" and e.get("type") == "response")
        assert "autoresearch_start" in probe()["active"], "reload lost startup tool"
        send({"id": "start", "type": "prompt", "message": "Start the approved fixture workflow"})
        result = until(lambda e: e.get("type") == "tool_execution_end" and e.get("toolName") == "autoresearch_start")
        assert not result.get("isError"), result
        assert "queued" in str(result["result"]).lower(), result
        if scenario == "clean":
            kickoff = until(lambda e: e.get("type") == "extension_ui_request" and '"kickoff":' in e.get("message", ""))
            kickoff = json.loads(kickoff["message"])
            assert kickoff["kickoff"] == "/skill:pi-autoresearch " + goal, kickoff
            after = probe()
            work = Path(after["cwd"])
            assert work.resolve() != root.resolve() and work.resolve().parent == directory.resolve()
            assert after["parent"] == before["session"]
            assert set(["autoresearch_start", "autoresearch_run", "autoresearch_log"]) <= set(after["active"])
            assert not (work / ".auto").exists(), "test accidentally started an experiment"
            parent_entries = [json.loads(line) for line in Path(before["session"]).read_text().splitlines()]
            assert any(e.get("message", {}).get("toolName") == "autoresearch_start" for e in parent_entries), "tool result lost from parent session"
            command("autoresearch off")
            until(lambda e: e.get("message") == "Autoresearch mode OFF")
            assert "autoresearch_start" in probe()["active"], "off hid startup tool"
            command("autoresearch cleanup")
            confirm = until(lambda e: e.get("type") == "extension_ui_request" and e.get("method") == "confirm")
            send({"type": "extension_ui_response", "id": confirm["id"], "confirmed": True})
            until(lambda e: e.get("type") == "extension_ui_request" and e.get("message", "").startswith("Removed "))
            assert not work.exists()
            assert probe()["session"] == before["session"]
        else:
            expected = "Autoresearch unavailable:" if scenario == "dirty" else "Session switch cancelled; created workspace rolled back"
            until(lambda e: e.get("type") == "extension_ui_request" and e.get("message", "").startswith(expected))
            assert Path(probe()["cwd"]).resolve() == root.resolve()
            assert list(directory.iterdir()) == [root], "failed startup left a workspace"
            if scenario == "dirty":
                assert (root / "dirty").read_text() == "preserve\n"
            if kind == "git":
                assert not run("git", "branch", "--list", "autoresearch/*", cwd=root)
        assert not any("Unexpected model continuation" in str(e) for e in seen), seen
        print(f"PASS {kind}/{scenario}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        errors = process.stderr.read()
        assert not errors, errors
