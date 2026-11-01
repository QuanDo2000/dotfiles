# Native bundled-CLI compaction regression replay

This opt-in check executes the actual published 1.4.0 CLI chunk's exported
`AgentSession`, not a replacement session, SDK class, rebuilt source, or live CLI.
It is deliberately separate from the lightweight Bash suite and full gates.

```sh
npm install --prefix tests/pi-compaction/node_modules/runner \
  --ignore-scripts --no-audit --no-fund vitest@4.1.11
installed=/nix/store/18gz6dd1v4lrjnxf3kdfhnw2hsafkb3k-pi-coding-agent-1.4.0/lib/node_modules/@earendil-works/pi-coding-agent
python3 tests/pi-compaction/run.py baseline "$installed" # expected exit 1, five failures
python3 tests/pi-compaction/run.py patched "$installed"  # expected exit 0, five passes
bash tests/bash/runner.sh test_pi_compaction_patch.sh
# Verify the Nix-built artifact itself, without repatching or copying its dist tree:
candidate=$(nix build path:.#pi-agent --no-link --print-out-paths)
python3 tests/pi-compaction/run.py installed \
  "$candidate/lib/node_modules/@earendil-works/pi-coding-agent"
```

`installed` mode links directly to the supplied package's read-only `dist` tree
and dependencies; it neither downloads the archive nor applies the patch. Use it
for the built or activated 1.4.0 package. Baseline/patched modes require the exact
original chunk as a source binding, so keep their `installed` argument pointing
to the original package shown above.

Prerequisites: Python 3, npm, Node (verified with v26.13.0), and the indicated
installed package's immutable dependency tree. Installation is local to this test
area, never production. The runner downloads the exact npm tarball only if absent,
checks the Nix-pinned SHA256, and checks the owning chunk matches the installed
original. Only the SDK target and owning bundle chunk differ in the patched copy.
It retains tarball, runner dependencies, isolated copies, complete native output
(`baseline.log`, `patched.log`) and Vitest JSON reports (`baseline.json`,
`patched.json`) under ignored `tests/pi-compaction/node_modules/`.

## Sources and boundaries

- `retirement.test.ts`: retained five-symptom reproducer from the authorized patch
  retirement investigation. Four paths run real auto-compaction with native session
  entries and extensions: supplied summary, error, synchronous abort on start,
  and extension cancellation. The late-steering test wraps the native settlement
  boundary with a scheduling barrier, preserving its actual return value; real
  prompt/input/queue/run/settlement methods determine delivery.
- `harness.ts`: retained upstream native suite harness, already bound to
  `dist/bundle/chunks/chunk-MM3LKT73.js` for this exact artifact; all other runtime
  imports bind to published SDK helpers. Types are erased by native Vitest.
- `prerequisites/test/{utilities,model-runtime-test-utils}.ts`: unchanged upstream
  prerequisites from commit `4a080252f06caf63a525d7873c5d94d3c23887e0`, fetched from
  `https://raw.githubusercontent.com/earendil-works/pi/4a080252f06caf63a525d7873c5d94d3c23887e0/packages/coding-agent/test/`.
  The runner only rebinds their `src/*.ts` imports to published `dist/*.js`.

Tests use the native faux provider, no live model or credentials. Each subprocess
gets a minimal environment with isolated HOME/XDG/Pi/temp paths. A preload rejects
fetch and HTTP/TCP/TLS connections. The error-mode auth spy is **not** an assertion
that it intercepts bundled internals: in this mixed SDK/bundle harness the real
summarizer fails locally with `No more faux responses queued`, as in the retained
baseline investigation. This still exercises the actual catch/end lifecycle.
This is native integration evidence, not full interactive-terminal E2E coverage.

## Observed A/B result

Exact original chunk SHA256:
`aa4c8b091657bda611f6fd58343561fa44cda1070ae4cd5dbd09ffe1d9a34aab`.
Baseline: five failures (exit 1), all four end listeners see `isCompacting=true`;
late steering is `queued`, pending=1/coreQueued=true after idle, with only the
initial user message and one faux call/settled event.
Patched: five passes (exit 0), all four listeners see `isCompacting=false`;
late steering is `started`, pending=0/coreQueued=false, both user messages and
two faux calls/settled events. Both variants reach idle after all four real
compaction paths. Lightweight Bash suite: 12 passed, zero failed.

The patch discovers the owning minified chunk by its auto-compaction method,
requires a unique owner and direct CLI runtime import, validates all three exact
boundaries and their patch states before either SDK/bundle write, and preserves
single-target SDK invocation and prior SDK-version support. The focused Bash
checks include idempotence, renamed chunk discovery, missing/duplicated/partially
patched boundaries, duplicate owners, patched-plus-original duplication, and
changed CLI linkage. No full gate, package build, activation, or publication is
performed by this replay.
