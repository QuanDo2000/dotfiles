# Dependency substitution parity

Use when deciding whether an installed package can be removed, replaced by an already-retained tool, or delegated to a native distribution package.

## Classify the comparison

- **Packaging substitution:** both choices deliver the same upstream application. Skip provider-backed A/B runs; compare release freshness, supported platforms, artifact provenance, runtime smoke behavior, closure, and update ownership.
- **Capability substitution:** a retained tool might cover another tool's job. Build a feature-level parity matrix before considering removal.
- **Dead dependency:** no real caller exists. Use static caller/ownership analysis rather than manufacturing a benchmark.

Keep the benchmark read-only. A favorable result authorizes a recommendation, not deployment.

## Packaging substitution protocol

1. Resolve the exact package versions from the locked repository input and the custom pin. Compare the candidate actually available to the deployment, not an unrelated current channel.
2. Build both packages and invoke provider-free surfaces such as `--version`, `--help`, feature listing, and local configuration listing.
3. Compare official static artifacts with distribution wrappers and patched builds. Record dynamic dependencies and supported platforms.
4. Measure direct NAR size, full closure size, and unique closure against everything that remains installed.
5. Trace coupled ownership before claiming line-count savings. A shared release file may still drive Windows installers, hashes, or cross-platform update logic; replacing only Unix packaging can retain most machinery while introducing version drift.
6. Treat startup microbenchmarks as startup-only. Alternate order, report sample count/median/mean/range/deviation, and never present `--version` timing as interactive-agent performance.

Prefer the custom package when it is materially newer or smaller and its pin/update machinery is already required elsewhere. Reconsider when the native package tracks upstream promptly and actually deletes shared ownership.

## Capability substitution protocol

1. Trace the real caller and invocation mode. For editor diagnostics, identify both the language server and standalone linter routes.
2. Freeze one minimal fixture per advertised rule or capability. Add syntax-error, semantic-error, unsupported-input, and clean controls so overlap and complementary behavior are visible.
3. Run both engines directly. If removal would alter an editor or service, also exercise that production route before deployment.
4. Report exact overlap, missed capabilities, unique findings on both sides, and false/noisy findings on the current repository.
5. Inspect real repository output. A candidate that emits mostly intentional style warnings may be noisy, but noise alone does not prove its unique rules are dispensable.
6. Apply the user's parity threshold before weighing small storage savings. Losing unique diagnostics is not near-full parity.

## Nix closure accounting

A package's closure is not its reclaimable cost. Report separately:

- package NAR size;
- package closure size;
- closure paths shared with retained roots;
- unique closure paths and summed unique NAR size;
- profile-path reduction after a real prototype, if authorized.

For a candidate and retained substitute, set-difference their recursive closures first. If every dependency is shared, the removable cost may be only the candidate's own store path. Do not promise reclaimed disk while old generations still retain it.

## Verdict shape

State one of: `keep`, `replace`, `remove`, or `revisit when <measurable trigger>`. Include the exact parity boundary, unique storage impact, cross-platform consequence, and what remained unverified.
