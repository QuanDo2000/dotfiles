# Info/Success/FailSoft output + Quiet-mode gating.

function test_info_prints_when_not_quiet {
    $script:Quiet = $false
    $output = Info 'hello world' 6>&1 | Out-String
    Assert-Contains $output 'hello world'
    Assert-Contains $output '..'
}

function test_info_silent_when_quiet {
    $script:Quiet = $true
    $output = Info 'hidden' 6>&1 | Out-String
    Assert-Equals '' ($output.TrimEnd([char]13, [char]10))
}

function test_success_prints_when_not_quiet {
    $script:Quiet = $false
    $output = Success 'done' 6>&1 | Out-String
    Assert-Contains $output 'done'
    Assert-Contains $output 'OK'
}

function test_success_silent_when_quiet {
    $script:Quiet = $true
    $output = Success 'hidden' 6>&1 | Out-String
    Assert-Equals '' ($output.TrimEnd([char]13, [char]10))
}

function test_failsoft_prints_even_when_quiet {
    # FailSoft must surface regardless of Quiet — errors are never silenced.
    $script:Quiet = $true
    $output = FailSoft 'boom' 6>&1 | Out-String
    Assert-Contains $output 'boom'
    Assert-Contains $output 'FAIL'
}
