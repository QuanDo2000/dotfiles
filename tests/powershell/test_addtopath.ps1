# Exercise real PATH logic with the suite's in-memory User PATH boundary.
# Native persistence is not tested against the logged-in account.

function TestSetup {
    $script:_OrigProcessPath = $env:Path
    $script:Quiet = $true
}

function TestTeardown {
    $env:Path = $script:_OrigProcessPath
}

function test_addtouserpath_dry_mode_does_not_modify_process_path {
    $script:Dry = $true
    $before = $env:Path
    AddToUserPath 'C:\nonexistent_test_dir_xyz'
    Assert-Equals $before $env:Path
}

function test_addtouserpath_already_present_does_not_duplicate_process_path {
    $script:Dry = $false
    $existing = 'C:\test-fixture-user-bin'
    Set-UserPath $existing
    if (-not (($env:Path -split ';') -contains $existing)) {
        $env:Path = "$env:Path;$existing"
    }

    $before = ($env:Path -split ';') | Where-Object { $_ -eq $existing } | Measure-Object
    AddToUserPath $existing
    $after = ($env:Path -split ';') | Where-Object { $_ -eq $existing } | Measure-Object

    Assert-Equals $before.Count $after.Count
    Assert-Equals $existing (Get-UserPath)
}

function test_addtouserpath_appends_once_to_isolated_user_and_process_path {
    Set-UserPath 'C:\existing'
    $env:Path = 'C:\process'
    AddToUserPath 'C:\new'
    AddToUserPath 'C:\new'
    Assert-Equals 'C:\existing;C:\new' (Get-UserPath)
    Assert-Equals 'C:\process;C:\new' $env:Path
}
