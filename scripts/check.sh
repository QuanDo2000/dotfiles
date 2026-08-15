#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="path:$repo_dir"
cd "$repo_dir"

if [[ "${DOTFILE_CHECK_IN_DEV_SHELL:-}" != "1" ]]; then
  exec nix develop "$flake" -c env DOTFILE_CHECK_IN_DEV_SHELL=1 bash "$repo_dir/scripts/check.sh"
fi

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run bash "$repo_dir/tests/bash/runner.sh"

run pwsh "$repo_dir/tests/powershell/runner.ps1"

run nix flake check "$flake" --no-build --all-systems
packages=(
  "$flake#codex"
  "$flake#pi-extensions"
  "$flake#fff-mcp"
  "$flake#fff-nvim-backend"
  "$flake#codebase-memory-mcp"
)
if [[ "$(uname -s)" == "Linux" ]]; then
  packages+=("$flake#obsidian-headless" "$flake#pi-agent")
fi
run nix build "${packages[@]}" --no-link
run shellcheck -S warning -e SC1090,SC1091,SC2034,SC2088,SC2120 dotfile scripts/*.sh tests/bash/*.sh
