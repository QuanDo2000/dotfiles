# Targeted Troubleshooting

Load when tracing deep failures, deciding where validation belongs, or diagnosing flaky asynchronous tests.

## Trace the first incorrect transition

Start at the observed symptom and follow the value/state backward through callers until the first incorrect assumption or transition. If static tracing is insufficient, use authorized, narrowly scoped instrumentation at the suspected boundary; capture inputs, resolved paths, environment differences, and call stack without secrets. Fix the shared cause and verify impacted callers.

For unexpected files created by tests, isolate the culprit in disposable state using the repository's runner. `find-polluter.sh` is an optional npm-oriented helper, not a generic runner or proof that failed tests passed; inspect its assumptions before use.

## Validate distinct boundaries

Reject invalid input at trust boundaries and enforce operation-specific invariants where dangerous effects occur. Add another guard only for a distinct bypass, caller, or failure mode; do not repeat the same check at every layer. Preserve security and data-loss protections. Logging aids diagnosis but is not validation, and passing tests do not make a bug impossible.

## Wait for conditions

Prefer the installed test framework's event, state, or polling assertions over sleeps or custom wait utilities. Read fresh state on each attempt, use a finite timeout, and include the expected condition and last observed state in failures. Choose polling intervals for the actual workload, not a universal millisecond constant.

When timing itself is the behavior (debounce, throttle, scheduler ticks), use the framework's controlled clock where appropriate. For real-time checks, first observe the triggering condition, then use a justified interval and account for scheduling noise. Do not replace required timing assertions with mere eventual success.
