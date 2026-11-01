#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="path:$repo_dir"
cd "$repo_dir"

if [[ "${DOTFILE_CHECK_IN_DEV_SHELL:-}" != "1" ]]; then
  exec nix develop "$flake" -c env DOTFILE_CHECK_IN_DEV_SHELL=1 bash "$repo_dir/scripts/check.sh"
fi

# All four stages read the same source and own their disposable mutable state.
# Three admission slots bound overlap: start Bash, PowerShell and Nix, then
# admit lint as a slot frees. Leaf worker limits are unchanged. These are
# source-independent stages, not prerequisites: collect all results even on
# failure. Nix still owns build-before-oracle ordering internally, including
# upstream's platform-specific Rex builds and Linux status oracle.
# Argument order preserves failure priority: Bash, PowerShell, Nix, then lint.
# The outer 5s grace exceeds Bash/lint's 3s and Nix/PS's 1s grace.
command=(python3 "$repo_dir/scripts/test_jobs.py" --jobs 3 --shared-run --cleanup-seconds 5 \
  --timeout 10800 --total-timeout 10803)
printf '\n==> %s\n' "${command[*]}"
exec "${command[@]}" --files "$repo_dir/scripts/check_bash.sh" "$repo_dir/scripts/check_powershell.sh" \
  "$repo_dir/scripts/check_nix.sh" "$repo_dir/scripts/check_lint.sh" -- bash
