#!/usr/bin/env bash
# Apply the reviewed single-file patch; never replace a complete upstream skill.
set -euo pipefail
fix="${1:?usage: apply_hermes_skill_fixes.sh PATCH_FILE [PATCH_BINARY]}"
patch_bin="${2:-patch}"
skill="$HOME/.hermes/skills/autonomous-ai-agents/hermes-agent"
target="$skill/references/security-privacy.md"
if [[ -L "$skill" || -L "$skill/references" || -L "$target" ]]; then
  printf 'Refusing symlinked Hermes security reference; review its owner.\n' >&2
  exit 1
fi
# Hermes is installed separately; re-run activation after first skill seeding.
[[ -f "$target" ]] || exit 0
if "$patch_bin" --force --fuzz=0 --reverse --dry-run "$target" "$fix" >/dev/null 2>&1; then
  exit 0
fi
if ! "$patch_bin" --batch --fuzz=0 --forward --dry-run "$target" "$fix" >/dev/null 2>&1; then
  printf 'Hermes security reference changed; review the tracked patch before activation.\n' >&2
  exit 1
fi
"$patch_bin" --batch --fuzz=0 --forward --no-backup-if-mismatch --reject-file=- "$target" "$fix"
