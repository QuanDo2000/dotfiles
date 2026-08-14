#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="path:$repo_dir"
cd "$repo_dir"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run nix develop "$flake" -c bash "$repo_dir/tests/bash/runner.sh"

run nix develop "$flake" -c pwsh "$repo_dir/tests/powershell/runner.ps1"

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
run nix develop "$flake" -c shellcheck -S warning -e SC1090,SC1091,SC2034,SC2088,SC2120 dotfile scripts/*.sh tests/bash/*.sh
