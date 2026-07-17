# Windows LazyVim synchronization tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_lazyvim_sync_verifies_installed_directories {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $lazyRoot = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy'
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-CommandMock 'nvim' {
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -like '*stdpath*') { Join-Path $env:LOCALAPPDATA 'nvim-data' }
    }

    try {
        $missingOutput = Sync-LazyVim 3>&1 | Out-String
        New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'lazy.nvim'), (Join-Path $lazyRoot 'LazyVim') | Out-Null
        $installedOutput = Sync-LazyVim 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
    }

    Assert-Contains $missingOutput 'LazyVim sync did not install'
    Assert-False ($installedOutput -like '*LazyVim sync did not install*') 'installed directories should satisfy LazyVim sync verification'
}

function test_getneovimcommand_uses_winget_fallback {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $nvim = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nvim.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path $nvim -Parent) | Out-Null
    New-Item -ItemType File -Path $nvim | Out-Null
    Set-CommandMock 'Get-Command' { return $null }

    try {
        $result = Get-NeovimCommand
    } finally {
        Clear-CommandMock 'Get-Command'
    }

    Assert-Equals $nvim $result
}

function test_sync_lazyvim_config_creates_writable_seed {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\config\nvim'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    '{"extras":[],"version":1}' | Set-Content (Join-Path $seedDir 'lazyvim.json')

    Sync-LazyVimConfig

    $target = Join-Path $env:LOCALAPPDATA 'nvim\lazyvim.json'
    $base = Join-Path $env:LOCALAPPDATA 'dotfiles\lazyvim-seed.json'
    Assert-FileExists $target
    Assert-FileExists $base
    Assert-False ([bool](Get-Item $target).LinkType) 'LazyVim config should stay writable'
}
