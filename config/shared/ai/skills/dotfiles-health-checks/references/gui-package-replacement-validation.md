# Validating managed GUI package replacements

Use when replacing a custom Nix package with a pinned nixpkgs equivalent or changing its packaging form.

## Rule

Same product/version and a successful build do not establish runtime parity. Package form can carry hidden runtime, sandbox, wrapper, desktop-integration, or security behavior.

## Workflow

1. Inventory behavior relied on by live configuration: tray, hide-on-close, permissions, screen sharing, file dialogs, protocol handlers, sandboxing, privacy controls, and persistent paths.
2. Build candidate without activation. Record exact output and compare closure, architecture support, updater behavior, and trust model.
3. Inspect launch wrappers and environment. Preserve variables and flags supplied by upstream Nix wrappers (`GIO_EXTRA_MODULES`, `GDK_PIXBUF_MODULE_FILE`, `XDG_DATA_DIRS`, Wayland/Ozone flags, etc.); never replace a wrapped executable with a raw copied binary without reproducing its contract.
4. Run both `--version` and a normal startup in an isolated `HOME` plus isolated XDG config/cache/state. Hash live configuration before and after. A version command passing while normal launch crashes is failure.
5. Check process survival, logs, exit signal/status, generated isolated config, and absence of live processes/config writes. Exercise safe GUI paths when a graphical session permits; list anything still manual.
6. Add candidate derivation to repository full-build coverage. Source-text assertions alone cannot prove overlay compatibility.
7. If credible parity requires brittle repacking, fuse mutation, wrapper reconstruction, or unverified GUI assumptions, revert the experiment and retain known-good packaging. Do not commit a no-op revert.

## Evidence to report

- Candidate and active store paths
- Build/check results
- Normal-start result, not only `--version`
- Live-config hash unchanged
- Wrapper/environment comparison
- Automated and unresolved manual parity checks
- Final tracked status and activation/commit/push state
