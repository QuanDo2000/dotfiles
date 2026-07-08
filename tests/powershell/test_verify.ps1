# Verify — drives the function end-to-end with mocked lookups. Verify uses
# $env:USERPROFILE (overridden by Initialize-TestEnv) so it operates on the
# temp home; tests still focus on control-flow coverage rather than asserting
# specific file-existence outcomes.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared') -Force | Out-Null
    # Create stub source files so Verify's Compare-Object call never throws on
    # missing sources when the real $HOME happens to contain matching dests.
    'g' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.gitconfig')
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared\.ssh') -Force | Out-Null
    'ssh' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.ssh\config')
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared\config') -Force | Out-Null
    's' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\config\starship.toml')
    # Verify's informational output flows through Info/Success, which are
    # gated by $script:Quiet. Keep Quiet off so 6>&1 captures the banners the
    # assertions look for.
    $script:Quiet = $false
}

function TestTeardown {
    Clear-CommandMock 'Get-Command'
    Clear-CommandMock 'Get-Module'
    Clear-TestEnv
}

function test_verify_emits_each_verification_phase {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'Verifying installed tools'
    Assert-Contains $output 'Verifying scoop packages'
    Assert-Contains $output 'Verifying PowerShell modules'
    Assert-Contains $output 'Verifying copied files'
    Assert-Contains $output 'Verifying neovim config'
}

function test_verify_checks_starship_config {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    # The starship config is among the copied files Verify checks; with the dest
    # absent in the temp home it reports the ~/.config/starship.toml path missing.
    Assert-Contains $output 'starship.toml'
}

function test_verify_fails_when_tracked_config_differs {
    Set-CommandMock 'Get-Command' {
        [pscustomobject]@{ Source = 'C:\fake\tool.exe' }
    }
    Set-CommandMock 'Get-Module' {
        [pscustomobject]@{ Name = 'FakeModule' }
    }
    New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE '.config') -Force | Out-Null
    'different git' | Set-Content (Join-Path $env:USERPROFILE '.gitconfig')
    'different starship' | Set-Content (Join-Path $env:USERPROFILE '.config\starship.toml')
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'nvim') -Force | Out-Null
    'init' | Set-Content (Join-Path $env:LOCALAPPDATA 'nvim\init.lua')

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'differs from source'
    Assert-True $script:VerifyFailed 'verify should fail when tracked config differs'
}

function test_verify_checks_shared_link_specs {
    Set-CommandMock 'Get-Command' {
        [pscustomobject]@{ Source = 'C:\fake\tool.exe' }
    }
    Set-CommandMock 'Get-Module' {
        [pscustomobject]@{ Name = 'FakeModule' }
    }
    New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE '.ssh') -Force | Out-Null
    'different ssh' | Set-Content (Join-Path $env:USERPROFILE '.ssh\config')

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output '.ssh'
    Assert-Contains $output 'differs from source'
    Assert-True $script:VerifyFailed 'verify should check shared file link specs'
}

function test_verify_reports_issues_when_tools_absent {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    # At least the six tool lookups should come back missing.
    Assert-Contains $output 'not found'
    Assert-Contains $output 'issue'
    Assert-True $script:VerifyFailed 'verify command dispatch should be able to exit nonzero'
}

function test_verify_reports_tools_found_when_mocks_return_objects {
    Set-CommandMock 'Get-Command' {
        [pscustomobject]@{ Source = 'C:\fake\tool.exe' }
    }
    Set-CommandMock 'Get-Module' {
        [pscustomobject]@{ Name = 'FakeModule' }
    }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'found'
    Assert-Contains $output 'installed'
}
