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
    Assert-True ($winget -contains 'Notepad++.Notepad++') 'Winget should manage Notepad++'
    Assert-True ($winget -contains 'koalaman.shellcheck') 'Winget should manage ShellCheck for Bash diagnostics'
    Assert-True ($scoop -contains 'FiraCode-NF') 'Scoop should manage FiraCode Nerd Font'
    Assert-False ($scoop -contains 'FiraCode') 'Regular FiraCode does not provide configured Nerd Font family'
    Assert-True ($scoop -contains 'jq') 'Scoop should manage jq'
    Assert-True ($scoop -contains 'ast-grep') 'Scoop should manage ast-grep'
    Assert-True ($commands -contains 'gh') 'Doctor should verify GitHub CLI'
    Assert-True ($commands -contains 'fff-mcp') 'Doctor should verify the Codex FFF MCP server'
    foreach ($command in 'vtsls', 'bash-language-server', 'shellcheck') {
        Assert-True ($commands -contains $command) "Doctor should verify Windows LSP dependency: $command"
    }
}

function test_windows_firacode_manifest_is_reviewed_and_immutable {
    $manifestPath = Join-Path $script:RepoDir 'config/windows/scoop/FiraCode-NF.json'
    Assert-FileExists $manifestPath
    if (-not (Test-Path -LiteralPath $manifestPath)) { return }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    Assert-Equals '3.5.0' $manifest.version
    Assert-Equals 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.0/FiraCode.zip' $manifest.url
    Assert-Equals '8ad2834d8ea1945d8ab042538e608f6370573a29913aa94b5e6bbc92ffacbab5' $manifest.hash

    $terminal = Get-Content -Raw -LiteralPath (Join-Path $script:RepoDir 'config/windows/Terminal/settings.json') | ConvertFrom-Json
    Assert-Equals 'FiraCode Nerd Font' $terminal.profiles.defaults.font.face
}
