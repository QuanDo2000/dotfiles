#!/usr/bin/env bash
# Complete native lint stage; preserve flags, discovery and deterministic reports.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

# debt: executor's 256-file ceiling; raise/revalidate before target 257.
lint_command=(python3 "$repo_dir/scripts/test_jobs.py" --jobs 8 --timeout 300)
# debt: Linux-measured compiler priorities; reprofile after target/compiler changes.
for name in scripts/releases.sh tests/bash/test_release_pins.sh tests/bash/test_home_profiles.sh; do
  if [[ -f "$name" ]]; then
    lint_command+=(--first "$name")
  fi
done
printf '\n==> %s\n' "${lint_command[*]}"
exec "${lint_command[@]}" --files dotfile scripts/*.sh tests/bash/*.sh -- \
  shellcheck -S warning -e SC1090,SC1091,SC2034,SC2088,SC2120
