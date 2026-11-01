#!/usr/bin/env python3
"""Replay five native symptoms against the pinned npm CLI bundle (no live provider).

Prerequisite: npm install --prefix tests/pi-compaction/node_modules/runner \
  --ignore-scripts --no-audit --no-fund vitest@4.1.11
Run: python3 tests/pi-compaction/run.py baseline|patched|installed INSTALLED_PI_ROOT
Artifacts/dependencies are retained under this directory's ignored node_modules/.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ARTIFACTS = HERE / "node_modules"
if len(sys.argv) != 3 or sys.argv[1] not in ("baseline", "patched", "installed"):
    raise SystemExit("Usage: run.py baseline|patched|installed INSTALLED_PI_ROOT")
mode, installed = sys.argv[1:]
installed = Path(installed).resolve()
ARTIFACTS.mkdir(exist_ok=True)
archive = ARTIFACTS / "pi-1.4.0.tgz"
if mode != "installed":
    if not archive.exists():
        with urllib.request.urlopen(
            "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.4.0.tgz", timeout=60
        ) as response:
            payload = response.read(32 * 1024 * 1024 + 1)
        if len(payload) > 32 * 1024 * 1024:
            raise SystemExit("Pinned archive exceeds 32 MiB download limit")
        archive.write_bytes(payload)
    if base64.b64encode(hashlib.sha256(archive.read_bytes()).digest()).decode() != "0VXBbvb6AJYPv1iykRU26AsF8zcA4LFPvQiWft4MdCg=":
        raise SystemExit("Pinned archive SHA256 mismatch")
root = ARTIFACTS / mode
if root.exists():
    shutil.rmtree(root)
root.mkdir()
if mode == "installed":
    (root / "dist").symlink_to(installed / "dist", target_is_directory=True)
else:
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if member.isfile() and member.name.startswith("package/dist/"):
                target = root / member.name.removeprefix("package/")
                target.parent.mkdir(parents=True, exist_ok=True)
                stream = tar.extractfile(member)
                assert stream is not None
                target.write_bytes(stream.read())
(root / "package.json").write_text('{"type":"module"}')
(root / "node_modules").symlink_to(installed / "node_modules", target_is_directory=True)
for src in (HERE / "prerequisites/test").glob("*.ts"):
    target = root / "test" / src.name
    target.parent.mkdir(exist_ok=True)
    # Bind native upstream test utilities to immutable published JS, not a TS rebuild.
    target.write_text(re.sub(r'(\.\./src/[^"\']+)\.ts',
                             lambda m: m[1].replace('../src/', '../dist/') + '.js', src.read_text()))
suite = root / "test/suite"
suite.mkdir()
for name in ("harness.ts", "retirement.test.ts"):
    shutil.copyfile(HERE / name, suite / name)
chunk = root / "dist/bundle/chunks/chunk-MM3LKT73.js"
if mode != "installed":
    assert hashlib.sha256(chunk.read_bytes()).hexdigest() == "aa4c8b091657bda611f6fd58343561fa44cda1070ae4cd5dbd09ffe1d9a34aab"
    assert chunk.read_bytes() == (installed / "dist/bundle/chunks" / chunk.name).read_bytes()
if mode == "patched":
    subprocess.run(["python3", str(REPO / "scripts/patch_pi_compaction.py"),
                    str(root / "dist/core/agent-session.js"), str(root / "dist/bundle")], check=True)
sandbox = root / "sandbox"
sandbox.mkdir()
preload = ARTIFACTS / "no-network.mjs"
preload.write_text('''import http from 'node:http'; import https from 'node:https';
import net from 'node:net'; import tls from 'node:tls';
import {syncBuiltinESMExports} from 'node:module';
const deny = () => { throw new Error('Native compaction verification forbids network'); };
globalThis.fetch = deny;
http.request = http.get = https.request = https.get = deny;
net.connect = net.createConnection = tls.connect = net.Socket.prototype.connect = deny;
syncBuiltinESMExports();
''')
env = {"PATH": os.environ["PATH"], "HOME": str(sandbox), "TMPDIR": str(sandbox),
       "XDG_CONFIG_HOME": str(sandbox / "config"), "XDG_CACHE_HOME": str(sandbox / "cache"),
       "PI_CODING_AGENT_DIR": str(sandbox / "pi"), "NO_COLOR": "1",
       "NODE_OPTIONS": f"--import={preload}"}
command = [shutil.which("node"), str(ARTIFACTS / "runner/node_modules/vitest/vitest.mjs"),
           "run", "--root", str(root), "test/suite/retirement.test.ts", "--maxWorkers=1",
           "--reporter=verbose", "--reporter=json", "--outputFile=" + str(ARTIFACTS / f"{mode}.json"),
           "--testTimeout=8000"]
with (ARTIFACTS / f"{mode}.log").open("w") as log:
    log.write(json.dumps(command) + "\n")
    log.flush()
    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=65)
report = json.loads((ARTIFACTS / f"{mode}.json").read_text())
print(json.dumps({"mode": mode, "exit": result.returncode, "passed": report["numPassedTests"],
                  "failed": report["numFailedTests"], "log": str(ARTIFACTS / f"{mode}.log")}))
# Baseline deliberately returns 1: do not mistake a supervisor success for green symptoms.
sys.exit(result.returncode)
