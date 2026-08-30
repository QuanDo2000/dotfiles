
function TestTeardown {
    Clear-CommandMock 'winget'
}



function test_windows_neovim_provisions_treesitter_build_tools {
    $packages = @(Get-WingetPackages)
    Assert-Contains ($packages -join "`n") "tree-sitter.tree-sitter-cli"
    Assert-Contains ($packages -join "`n") "LLVM.LLVM"
    Assert-Contains ((Get-RequiredCommands) -join "`n") "tree-sitter"
    Assert-Contains ((Get-RequiredCommands) -join "`n") "clang"
}

function test_windows_package_manifests_cover_parity_tools {
    $winget = @(Get-WingetPackages)
    $commands = @(Get-RequiredCommands)

    Assert-True ($winget -contains 'Microsoft.PowerShell') 'Winget should manage PowerShell'
    Assert-True ($winget -contains 'Neovim.Neovim') 'Winget should manage Neovim'
    Assert-True ($winget -contains 'Python.Python.3.14') 'Winget should manage Python for shared seed scripts'
    Assert-True ($winget -contains 'GnuPG.Gpg4win') 'Winget should manage Gpg4win'
    Assert-True ($winget -contains 'Notepad++.Notepad++') 'Winget should manage Notepad++'
    Assert-True ($winget -contains 'koalaman.shellcheck') 'Winget should manage ShellCheck for Bash diagnostics'
    foreach ($package in 'junegunn.fzf', 'jqlang.jq', 'GitHub.cli') {
        Assert-False ($winget -contains $package) "Winget should not manage unused Windows package: $package"
    }
    foreach ($command in 'fzf', 'jq', 'gh') {
        Assert-False ($commands -contains $command) "Doctor should not require unused Windows command: $command"
    }
    foreach ($command in 'vtsls', 'bash-language-server', 'shellcheck') {
        Assert-True ($commands -contains $command) "Doctor should verify Windows LSP dependency: $command"
    }
}

function test_windows_firacode_release_is_reviewed_and_immutable {
    Assert-True ($script:FiraCodeNerdFontVersion -match '^\d+\.\d+\.\d+$') 'font version should be exact semver'
    Assert-Equals "https://github.com/ryanoasis/nerd-fonts/releases/download/v$script:FiraCodeNerdFontVersion/FiraCode.zip" $script:FiraCodeNerdFontUrl
    Assert-True ($script:FiraCodeNerdFontSha256 -match '^[0-9a-f]{64}$') 'font archive should have a SHA-256 pin'

    $terminal = Get-Content -Raw -LiteralPath (Join-Path $script:RepoDir 'config/windows/Terminal/settings.json') | ConvertFrom-Json
    Assert-Equals 'FiraCode Nerd Font' $terminal.profiles.defaults.font.face
}
