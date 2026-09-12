# Hermes workflow skills

These are the approved local Hermes adaptations of `requesting-code-review`,
`subagent-driven-development`, `writing-plans`, `plan`, and
`test-driven-development`, including all three referenced documents. Their
frontmatter attribution and reference-level provenance are retained unchanged.
The source snapshot is the default profile's `skills/software-development/`
tree, after the workflow simplification; it is not an unmodified upstream release.
No machine-specific absolute paths were present in that snapshot.

## Ownership and deployment

`config/home.nix` links each complete directory into
`~/.hermes/skills/software-development/<name>` on Unix. Only the default Hermes
profile is managed. No Windows installer or other Hermes profile is changed.
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

## Provenance

The skill frontmatter credits Hermes Agent, obra/superpowers, and MorAlekss as
applicable. The shared [superpowers MIT notice](../skills/licenses/superpowers-MIT.txt)
credits Jesse Vincent. The two subagent references retain their MIT attribution
to Lex Christopherson and link to `gsd-build/get-shit-done`. Local additions include
read-only review, failure-signal auditing, review of clean/jj-managed checkouts,
one-writer delegation, plan-only boundaries, and preservation of existing work
when establishing RED/GREEN evidence. Preserve these when updating upstream text.
