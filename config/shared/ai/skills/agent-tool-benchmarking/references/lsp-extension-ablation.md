# LSP extension removal ablations

Use this supplement when deciding whether an agent-side LSP extension should load by default, remain on demand, or be replaced by repository-native checks.

## Canonical natural-selection coverage

Keep prompts outcome-only and score executable artifacts. Use paired mutation workloads across every configured language server:

1. root-cause diagnosis plus minimal fix;
2. semantic diagnostic repair;
3. caller-preserving cross-file refactor;
4. multi-file implementation;
5. regression-test repair;
6. incremental edits and stale-diagnostic resistance;
7. mixed-language change;
8. a control where LSP should abstain.

Authoritative native tests, type checks, evaluators, and shell checks must be identical in both variants. LSP output can accelerate diagnosis, but it does not replace completion validation.

## Provider-free conformance supplement

Exercise every released tool and parameter separately from natural adoption: file and directory routing, severities, limits, preview/write fixes, unsupported files, malformed config, missing server, timeout, crash/restart, cancellation, workspace-root boundaries, stale/current file content, and cleanup. Prove each configured server actually executes; configuration presence is not runtime coverage.

## Lifecycle accounting

Measure extension-only startup/RSS separately from selected-call server costs. Record first-call latency, repeated-call latency, process-tree peak RSS, and process lifetime. Check whether the extension starts a fresh server per call: if so, do not describe the second call as a persistent warm session or claim incremental-session amortization.

## Interpretation

Report natural selection, calls, tool-level errors, successful diagnostic payloads, native-check use, repair cycles, and paired quality wins/losses/ties. Inspect error payloads before classifying utility: an error-status result may still contain useful diagnostics, while repeated timeouts with tied executable quality support native-default or on-demand use. Preserve explicit utility when conformance succeeds even if default-on exposure loses.

Coverage-balanced language matrices are not workload-frequency measurements. Give a decision table for default-on, on-demand, native-default, and full removal, bounded to configured languages and released capabilities.

Do not retain an on-demand integration merely because conformance proves it can work. Require a recurring use that native checks do not cover; otherwise complete removal is cheaper than maintaining speculative configuration, and the package can be reinstalled when a real need appears.

Distinguish the agent extension from its underlying language-server binaries. Removing the extension does not justify removing servers used by editors or other tools; trace those consumers and audit the binaries separately.
