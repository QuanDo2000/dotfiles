# Hermes workflow skills

These are the approved local Hermes adaptations of `requesting-code-review`,
`subagent-driven-development`, `writing-plans`, `plan`,
`test-driven-development`, `systematic-debugging`, and `multi-agent-orchestration`,
including their complete reference trees. Their frontmatter attribution and
reference-level provenance are retained unchanged.
The source snapshot is the default profile's `skills/software-development/` and
`skills/autonomous-ai-agents/` trees, after the workflow simplification; it is not
an unmodified upstream release.
No machine-specific absolute paths were present in that snapshot.

## Ownership and deployment

`config/home.nix` links each complete directory into
`~/.hermes/skills/software-development/<name>` on Unix, except orchestration at
`~/.hermes/skills/autonomous-ai-agents/multi-agent-orchestration`. Only the default
Hermes profile is managed. No Windows installer or other Hermes profile is changed.
The distinct shared Codex/Pi TDD adaptation under `../skills/` remains separate;
do not install both adaptations into the same runtime or add this tree to Pi's
skill search paths.

Home Manager deliberately uses `force = false` for these directories. Before
first activation, compare any existing local copy with this source and move it
to a timestamped backup outside the skill search tree. Do not overwrite a Nix
store target. Activate through the repository's normal platform route (or its
`_home_manager_switch` helper for a profile-only switch without pin updates or
root-owned installers), then verify all files and Hermes discovery. If activation
fails before installing the links, restore only the missing skill directories
from that backup.

After deployment these skills are immutable Home Manager links. Make future
changes here, not through `skill_manage` on the installed copy; run the focused
profile tests and full `./scripts/check.sh` before activating and committing.
Other local Hermes skills remain writable and unmanaged.

## Update boundary

Hermes' bundled updater (`tools/skills_sync.py`) preserves a directory when its
content differs from the recorded origin, and refuses a different existing local
copy when no origin is recorded. Our adaptations use that native protection;
immutable symlinks alone are not an updater ownership guard. Do not reset/rebaseline,
force-install, or uninstall these names through Hermes. A legacy hashless manifest
can adopt local content as its origin; resolve that state before running updates.
Recheck the actual updater in isolated fixtures after changing ownership or origin
metadata. Normal update preservation is not a promise about forced operations or
future updater implementations.

The shared Codex/Pi adaptations in `../skills/` have `updateMode: "manual"` in
`sources.json`. `scripts/update_pins.py skills` keeps their complete directories,
local additions, license, and recorded upstream commit/archive hash unchanged;
it does not label an unreviewed upstream revision as incorporated. To refresh,
compare upstream in a temporary checkout, merge selected changes into tracked
sources while preserving adaptations, and update provenance only after review.
Do not remove the manual policy just to obtain a newer pin. The Hermes tree is
outside that updater's replacement root.

The Hermes debugging adaptation retains service-manager environment/interpreter
checks, investigation-only prohibitions, data-flow tracing, and a measured
performance loop. Its trim removes repeated persuasion, fixed-attempt rhetoric,
and unattributed performance claims, not those locally learned safeguards.

## Security reference correction (default profile, Unix)

`security-privacy.patch` owns the correction to the bundled `hermes-agent`
reference. It is an upstream-compatible, single-hunk patch against
`skills/autonomous-ai-agents/hermes-agent/references/security-privacy.md` at
NousResearch/hermes-agent revision `284d220ba48e25f2e3623b3afe72db8f24a4c2db`
(MIT; original skill attribution remains installed). No complete upstream skill
is duplicated or replaced: every other reference, template, and local addition
stays in place. The owning deployment path is `config/home.nix` activation
`patchHermesSecurityReference` → `scripts/apply_hermes_skill_fixes.sh`.

The helper uses Nix's GNU patch, accepts an already-applied patch, rejects source
drift and symlinked skill/reference targets, and leaves a missing installation
alone. Back up the complete skill before first application. If Hermes is installed
or its skills are first seeded **after** Home Manager, re-run the normal profile
activation. Windows and non-default Hermes profiles are intentionally unmanaged.
The patch changes documentation only, never approval policy or Hermes core.

The reference distinguishes routine command approval from per-operation protected
instruction-file approval, including non-interactive worker denial that can be
misreported as a human rejection. After denial/timeout, stop; only renewed user
authorization permits retry through the same normal gate. Never change protection
or an allowlist to get past denial. Implementation sources:
`tools/file_tools_write_guards.py:208-288` and `tools/delegate_tool_config.py:35-59`.
The [official security documentation](https://hermes-agent.nousresearch.com/docs/user-guide/security/)
still omits this project-instruction gate in its file-write overview; installed
source is the evidence for this correction.

Ordinary bundled sync recognizes the changed complete-directory hash and preserves
**the entire skill**, not just this reference. Thus future upstream skill updates
require review, just as with the full-directory adaptations above. Existing/fresh
origin manifests and changed upstream revisions must be tested in temporary
fixtures when changing the patch. Hashless/rebaselined origins, forced resets,
upstream convergence to identical content, and future updater behavior remain
outside this guarantee; never use reset/rebaseline to silence update notices.
Once upstream incorporates the correction, review and retire the patch deliberately.

## Nix trust warning: investigated, intentionally not suppressed

`tools/skills_tool.py:505-517` resolves skill symlinks before comparing trusted
roots. Home Manager targets consequently load but warn as outside the profile's
skills directory. The documented `skills.external_dirs` setting resolves exact
paths and can remove this warning without disabling content-pattern scanning.
However, it is **discovery and ownership configuration, not a trust-only switch**.
No separate supported resolved-symlink trust list was found in this runtime.

An isolated real-runtime probe with the seven exact managed skill paths removed
all seven outside-root warnings, but reproduced an updater failure when a bundled
revision matches an externally indexed managed skill. In
`tools/skills_sync.py:262-272`, `_defer_to_external` tries to remove the local shadow;
`_rmtree_writable` at lines 419-432 then refuses its resolved external target as
not strictly under the local skills root. The scope guard correctly prevents
deletion, but `sync_skills` raises `ValueError`. Do not weaken that guard.
The [external-directory documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/#external-skill-directories)
also describes ownership implications; it is not an approval setting.

The existing warning is therefore retained pending an upstream-supported trust-only
solution or separately authorized ownership migration/core work. No trust for
`/nix/store`, extra search roots, scanner exclusions, approval changes, or other
profile settings are installed by this correction.

## Provenance

The skill frontmatter credits Hermes Agent, obra/superpowers, and MorAlekss as
applicable. The shared [superpowers MIT notice](../skills/licenses/superpowers-MIT.txt)
credits Jesse Vincent. The two subagent references retain their MIT attribution
to Lex Christopherson and link to `gsd-build/get-shit-done`. Local additions include
read-only review, failure-signal auditing, review of clean/jj-managed checkouts,
one-writer delegation, plan-only boundaries, and preservation of existing work
when establishing RED/GREEN evidence. Preserve these when updating upstream text.
