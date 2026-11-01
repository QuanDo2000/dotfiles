#!/usr/bin/env bash
# Complete Bash stage; standalone runner semantics remain unchanged.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

bash_command=(python3 "$repo_dir/scripts/test_jobs.py" --jobs 6 --timeout 300)
# debt: Linux-measured file priorities; remeasure when a different file is critical.
for name in test_home_profiles.sh test_pins.sh test_restic_recovery.sh test_release_pins.sh; do
  if [[ -f "$repo_dir/tests/bash/$name" ]]; then
    bash_command+=(--first "$repo_dir/tests/bash/$name")
  fi
done
printf '\n==> %s\n' "${bash_command[*]}"
exec "${bash_command[@]}" --files "$repo_dir"/tests/bash/test_*.sh -- bash "$repo_dir/tests/bash/runner.sh"
