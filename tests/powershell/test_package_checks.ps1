# WingetHas with native-command mocks.

function TestTeardown {
    Clear-CommandMock 'winget'
}

function test_wingethas_true_when_exit_zero {
    Set-CommandMock 'winget' {
        $global:LASTEXITCODE = 0
        'Git.Git 2.0'
    }
    Assert-True (WingetHas 'Git.Git') 'WingetHas should return true on exit 0'
}

function test_wingethas_false_when_exit_nonzero {
    Set-CommandMock 'winget' {
        $global:LASTEXITCODE = 1
    }
    Assert-False (WingetHas 'Nonexistent.Package') 'WingetHas should return false on non-zero exit'
}

function test_windows_package_manifests_cover_parity_tools {
    $winget = @(Get-WingetPackages)
    $scoop = @(Get-ScoopPackages)
    $commands = @(Get-RequiredCommands)

    Assert-True ($winget -contains 'Microsoft.PowerShell') 'Winget should manage PowerShell'
    Assert-True ($winget -contains 'Neovim.Neovim') 'Winget should manage Neovim'
    Assert-True ($winget -contains 'Python.Python.3.14') 'Winget should manage Python for shared seed scripts'
    Assert-True ($winget -contains 'GitHub.cli') 'Winget should manage GitHub CLI'
    Assert-True ($winget -contains 'GnuPG.Gpg4win') 'Winget should manage Gpg4win'
    Assert-True ($scoop -contains 'FiraCode') 'Scoop should manage FiraCode'
    Assert-True ($scoop -contains 'jq') 'Scoop should manage jq'
    Assert-True ($scoop -contains 'ast-grep') 'Scoop should manage ast-grep'
    Assert-True ($commands -contains 'gh') 'Doctor should verify GitHub CLI'
}
