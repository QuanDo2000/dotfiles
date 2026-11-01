#!/usr/bin/env pwsh
# Unix gate only. Normal profile startup occurs once in THIS parent, as before.
# Fresh child engines inherit its environment, not mutable functions/global state;
# -NoProfile avoids repeating user startup. Explicit profile tests still execute.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# debt: executor accepts at most 256 files; raise/revalidate before file 257.
$files = @(Get-ChildItem -Path $PSScriptRoot -Filter 'test_*.ps1' | Sort-Object Name | ForEach-Object { $_.FullName })
if ($files.Count -eq 0) { throw 'No PowerShell test files found.' }
$worker = Join-Path $PSHOME 'pwsh'
& python3 (Join-Path $repo 'scripts/test_jobs.py') --jobs 4 --cleanup-seconds 1 --timeout 10800 --total-timeout 10803 --files @files -- $worker -NoProfile (Join-Path $PSScriptRoot 'runner.ps1')
exit $LASTEXITCODE
