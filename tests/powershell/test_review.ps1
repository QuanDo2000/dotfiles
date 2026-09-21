function test_review_targets_require_clean_exact_commits {
    node --test (Join-Path $script:RepoDir 'tests/fixtures/review-target.test.mjs')
    Assert-Equals 0 $LASTEXITCODE
}

function test_review_sdk_isolation_and_tool_dispatch {
    $pi = Get-Command pi -ErrorAction SilentlyContinue
    if (-not $pi) { Skip-Test 'Pi unavailable; covered by pinned Unix integration suite'; return }
    $python = Get-Command py, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'Python unavailable; review integration requires py or python3' }
    & $python.Source (Join-Path $script:RepoDir 'tests/fixtures/review-integration.py') $pi.Source
    Assert-Equals 0 $LASTEXITCODE
}
