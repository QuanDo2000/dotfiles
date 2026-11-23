# Shared skills

Home Manager owns Unix links under `~/.agents/skills/`; Windows `InstallAiSkills`
installs complete directories there with the existing staged-copy/rollback helper.
Pi discovers this native shared location. Do not add duplicate Pi copies.

`test-driven-development` is now discovered as `tdd` in Pi; the separate
Hermes-native workflow keeps its original name. Windows moves any retired shared
or Pi copy outside skill discovery after installing the replacement, preserving
its contents for review. Unix Home Manager removes its old managed link on
activation; inspect collisions before activation. Existing sessions may retain
the old catalog until restarted.

`skill-retrospective` covers current-conversation reflection and bounded audits
of past conversations. The standalone `reflect` and `blast-radius` skills are
retired. Unix removes their managed links on activation; Windows leaves existing
copies in place, so they may remain discoverable until manually removed.

`unslop` is retired: request scoped prose edits directly. Home Manager removes
its managed link on activation. Windows moves existing shared and Pi copies to
name-specific backups outside discovery, preserving local additions.

## Promoted local workflows

| Shared name | Original/default Unix Hermes path |
|---|---|
| `github-code-review` | `~/.hermes/skills/github/github-code-review` |
| `github-pr-workflow` | `~/.hermes/skills/github/github-pr-workflow` |
| `dotfiles-health-checks` | `~/.hermes/skills/devops/dotfiles-health-checks` |
| `agent-tool-benchmarking` | `~/.hermes/skills/evaluation/agent-tool-benchmarking` |

These complete, reusable trees were promoted from authorized local Hermes
adaptations. Each `UPSTREAM.md` records provenance, changes, and assumptions.
They contain guidance and examples, not credentials, sessions, databases, or
executable maintenance helpers. Benchmark case histories are inherited,
version-scoped examples—not newly verified empirical results. Host addresses
are placeholders; runtime/version/role assumptions must be resolved before use.

Hermes does not use the shared discovery location in this deployment, so Unix
links each existing native path to the same tracked tree. This is not a second
adaptation or an extra search root. Windows installs shared Pi skills only;
Windows Hermes and non-default Hermes profiles remain unmanaged. The separate
Hermes workflow adaptations under `../hermes/skills/` retain their ownership.

## First activation and rollback

New shared and native Hermes links deliberately have `force = false`:

1. Build/check the intended host-role profile without switching or refreshing pins.
2. Compare complete existing directories with the reviewed source. Preserve any
   unexpected/concurrent changes; stop rather than overwrite them.
3. Verify tracked installation and discovery in an isolated fixture. Only then
   move colliding local copies to a private, timestamped backup **outside every
   skill search tree**. Do not delete the only local copy.
4. Activate through the repository's role-aware route. Compare every deployed
   file/reference, require each promoted name exactly once per intended harness,
   and check the final worktree. Existing sessions may need a fresh start.
5. If activation fails, inspect partial state. Restore only missing paths from
   backup; never overwrite a new generation, concurrent copy, or store target.
   Keep the backup and prior generation until live verification succeeds.

For `systematic-debugging` and `skill-retrospective`, Windows retains a previous
shared copy in `~/.agents/retired-skills/` before replacement and leaves old Pi
copies alone. On a failed verification, follow the reported backup path for manual
recovery; linked destinations are refused. Other skills retain existing installer
behavior. Cross-platform PowerShell tests do not establish native Windows discovery.

## Update ownership

These four local packages are manually maintained; they have no fabricated
upstream pin. `scripts/update_pins.py skills` updates only declared upstream
entries in `sources.json` and preserves other complete directories. Existing
shared upstream adaptations retain their explicit manual-update entries.

Hermes' bundled updater preserves differing local content or a different existing
copy with no recorded origin. Test native sync against temporary symlink fixtures
with fresh/existing manifests and changed upstream revisions. A symlink alone is
not an ownership guard: hashless/rebaselined origins, upstream convergence,
forced resets, and future updater behavior remain outside the guarantee. Do not
reset, rebaseline, force-install, or uninstall these names through Hermes.

Do not add `/nix/store` or these links to Hermes `skills.external_dirs` merely to
suppress trust warnings; that changes discovery/updater ownership. See
`../hermes/README.md` for the tested limitation. Normal link resolution warnings
remain visible; approval/scanning safeguards are unchanged.
