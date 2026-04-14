#!/usr/bin/env pwsh
# Framework-free Pester-equivalent runner. Mirrors tests/runner.sh:
#   - Discover `test_*` functions in each test_*.ps1 file
#   - Run each inside a reset state with optional TestSetup/TestTeardown
#   - Collect failures via $script:Errors, then print summary + exit code

$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = $PSScriptRoot
. (Join-Path $SCRIPT_DIR 'helpers.ps1')

$TestFile = if ($args.Count -gt 0) { $args[0] } else { $null }

$Total = 0
$Passed = 0
$Failed = 0

function Run-TestFile($file) {
    Write-Host "--- $(Split-Path $file -Leaf) ---"

    # Remember the set of test_* functions that existed BEFORE we source the
    # file, so we only discover the ones this file defined.
    $preexisting = @{}
    Get-Command -CommandType Function -Name 'test_*' -ErrorAction SilentlyContinue |
        ForEach-Object { $preexisting[$_.Name] = $true }

    . $file

    $tests = Get-Command -CommandType Function -Name 'test_*' -ErrorAction SilentlyContinue |
        Where-Object { -not $preexisting.ContainsKey($_.Name) } |
        Select-Object -ExpandProperty Name

    if (-not $tests) {
        Write-Host "  (no test_* functions found)"
        return
    }

    $hasTestSetup = [bool](Get-Command -Name 'TestSetup' -CommandType Function -ErrorAction SilentlyContinue)
    $hasTestTeardown = [bool](Get-Command -Name 'TestTeardown' -CommandType Function -ErrorAction SilentlyContinue)

    foreach ($t in $tests) {
        $script:Total++
        $script:Errors = [System.Collections.Generic.List[string]]::new()
        Reset-DotfileState

        $exitCode = 0
        $caught = $null
        try {
            if ($hasTestSetup) { TestSetup }
            & $t
        } catch {
            $exitCode = 1
            $caught = $_
        } finally {
            if ($hasTestTeardown) {
                try { TestTeardown } catch { }
            }
        }

        if ($exitCode -ne 0 -or $script:Errors.Count -gt 0) {
            $script:Failed++
            Write-Host "  FAIL  $t" -ForegroundColor Red
            if ($caught) { Write-Host "    (exception: $($caught.Exception.Message))" }
            foreach ($e in $script:Errors) { Write-Host $e }
        } else {
            $script:Passed++
            Write-Host "  PASS  $t" -ForegroundColor Green
        }
    }

    # Remove discovered tests + TestSetup/TestTeardown so they don't leak between files.
    foreach ($t in $tests) { Remove-Item "function:\$t" -ErrorAction SilentlyContinue }
    Remove-Item 'function:\TestSetup' -ErrorAction SilentlyContinue
    Remove-Item 'function:\TestTeardown' -ErrorAction SilentlyContinue
}

$files = if ($TestFile) {
    @(Join-Path $SCRIPT_DIR $TestFile)
} else {
    Get-ChildItem -Path $SCRIPT_DIR -Filter 'test_*.ps1' | Sort-Object Name | ForEach-Object { $_.FullName }
}

if (-not $files) {
    Write-Host "No test files found."
    exit 1
}

foreach ($f in $files) { Run-TestFile $f }

Write-Host ""
Write-Host "=== Results: $Passed passed, $Failed failed, $Total total ==="
if ($Failed -gt 0) { exit 1 }
exit 0
