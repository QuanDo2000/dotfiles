# Codex Skill Deduplication

## Goal

Keep Superpowers' debugging, TDD, and verification disciplines without loading
its planning, delegation, review, and branch-management workflows.

## Declarative setup

- Pin `obra/superpowers` tag `v6.1.1` once in `config/home.nix`.
- Home Manager exposes the complete upstream directories for:
  - `systematic-debugging`
  - `test-driven-development`
  - `verification-before-completion`
- Remove the enabled `superpowers@openai-curated` plugin entry from the tracked
  Codex seed and the writable live Codex config.
- Add focused Home Manager tests proving exactly those three Superpowers skill
  directories are managed and the full plugin is disabled.

## Local cleanup

- Remove `.agents/skills/caveman`, which is byte-identical to the globally
  managed Caveman skill.
- Remove `.agents/skills/cavecrew`, which duplicates delegation orchestration
  that is disabled by default.
- Keep the specialized Caveman commit, review, compression, help, and stats
  skills.
- Delete cached Superpowers plugin versions and the abandoned marketplace
  staging checkout after the declarative replacement is verified.
- Keep the OpenAI templates cache because it is unrelated to this duplication.

## Verification

- Run the focused Home Manager/Nix configuration tests.
- Parse both Codex TOML files after removing the plugin entry.
- Run the repository's full check before committing.
- Confirm the live skill directories resolve to the pinned Home Manager source
  after activation; until activation, the existing plugin remains available
  only through its cache and current process.
