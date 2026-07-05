# AddToUserPath — only exercises branches that do NOT persist to the user
# environment. Dry mode and "already-present" short-circuit before the
# SetEnvironmentVariable call, so they're safe to run in CI.

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
    # Use the first existing user PATH entry so we hit the "already present"
    # branch without having to write to the user registry.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $existing = @($userPath -split ';' | Where-Object { $_ })[0]
    if (-not $existing) { return }
    if (-not (($env:Path -split ';') -contains $existing)) {
        $env:Path = "$env:Path;$existing"
    }

    $before = ($env:Path -split ';') | Where-Object { $_ -eq $existing } | Measure-Object
    AddToUserPath $existing
    $after = ($env:Path -split ';') | Where-Object { $_ -eq $existing } | Measure-Object

    Assert-Equals $before.Count $after.Count
}
