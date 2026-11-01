#!/usr/bin/env bash
# Internal Unix gate stage; keep the native PowerShell runner unchanged.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if command -v pwsh >/dev/null 2>&1; then
  printf '\n==> pwsh %s\n' "$repo_dir/tests/powershell/parallel.ps1"
  exec pwsh "$repo_dir/tests/powershell/parallel.ps1"
fi
printf 'SKIP: PowerShell suite unavailable (pwsh not found)\n'
