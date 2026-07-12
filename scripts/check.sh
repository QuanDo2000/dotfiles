#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run bash "$repo_dir/tests/bash/runner.sh" --no-docker

if command -v pwsh >/dev/null 2>&1; then
  run pwsh "$repo_dir/tests/powershell/runner.ps1"
else
  printf '\n==> Skipping PowerShell tests: pwsh not found\n'
fi

run nix flake check --no-build --all-systems
run nix build "$repo_dir#codex" "$repo_dir#obsidian-headless" "$repo_dir#pi-agent" --no-link
run nix develop "$repo_dir" -c shellcheck -S warning -e SC1090,SC1091,SC2034,SC2088,SC2120 dotfile scripts/*.sh tests/bash/*.sh
