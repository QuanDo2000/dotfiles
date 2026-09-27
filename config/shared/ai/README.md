# Agent policy and skill ownership

- `AGENTS.md` owns the common startup policy for Hermes and Pi. Its `Skill Promotion` and `Pi Autoresearch` sections apply only to Pi. Unix Home Manager installs the complete file for Pi; the Windows installer copies it for Pi.
- `SOUL.md` owns Hermes identity only. `config/home.nix` composes the complete installed Hermes policy from this file and the common section of `AGENTS.md`, stopping before `Skill Promotion`. A missing or renamed boundary fails Nix evaluation rather than silently dropping or adding rules. Do not edit the generated store file.
- `skills/` owns shared Pi task procedures. Four promoted skills (`github-code-review`, `github-pr-workflow`, `dotfiles-health-checks`, `agent-tool-benchmarking`) are also linked into Hermes from the **same** tracked directories.
- `hermes/skills/` owns Hermes-specific adapters and their assets. `plan` controls plan-only writes; `writing-plans` controls plan content. `requesting-code-review` controls static review; `github-code-review` adds the GitHub PR target. `subagent-driven-development` controls implementation handoffs; `multi-agent-orchestration` controls runtime selection and recovery. Shared and Hermes TDD/debugging adaptations remain separately installed because their consumers load different skill trees; do not install both versions into one runtime.

See `hermes/README.md` and `skills/README.md` for deployment, provenance, and updater boundaries. Installed bundled/user-local Hermes skills are not owned by this directory; review their provenance before changing or retiring one.
