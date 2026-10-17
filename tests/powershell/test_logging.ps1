function test_logging_format_and_continuation {
    $output = & { Info "path\name`nnext line"; Success 'Done'; Ask 'Choose'; FailSoft 'Failed' } 6>&1 | ForEach-Object { $_.ToString() }
    Assert-Equals "  [INFO] path\name`n         next line" $output[0]
    Assert-Equals '  [ OK ] Done' $output[1]
    Assert-Equals '  [ASK ] Choose' $output[2]
    Assert-Equals '  [FAIL] Failed' $output[3]
}

function test_logging_quiet_preserves_failure_and_prompt {
    $script:Quiet = $true
    $output = & { Info 'Hidden'; Success 'Hidden'; Ask 'Choose'; FailSoft 'Failed' } 6>&1 | ForEach-Object { $_.ToString() }
    Assert-Equals 2 $output.Count
    Assert-Equals '  [ASK ] Choose' $output[0]
    Assert-Equals '  [FAIL] Failed' $output[1]
}

function test_logging_dry_run_does_not_claim_success {
    $script:Dry = $true
    $output = & { Info 'Would install packages'; Success 'Finished installing packages' } 6>&1 | ForEach-Object { $_.ToString() }
    Assert-Equals '  [DRY ] Would install packages' ($output -join "`n")
}
