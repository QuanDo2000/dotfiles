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
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $originalGetDataPath = (Get-Command Get-NeovimDataPath).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-FunctionMock 'Get-NeovimDataPath' { Join-Path $env:LOCALAPPDATA 'nvim-data' }
    Set-CommandMock 'nvim' { $global:LASTEXITCODE = 0 }

    try {
        $output = Sync-LazyVim 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
        Set-FunctionMock 'Get-NeovimDataPath' $originalGetDataPath
    }

    Assert-Contains $output 'LazyVim sync did not install'
}

function test_lazyvim_sync_accepts_installed_directories {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $lazyRoot = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy'
    New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'lazy.nvim') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'LazyVim') | Out-Null
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $originalGetDataPath = (Get-Command Get-NeovimDataPath).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-FunctionMock 'Get-NeovimDataPath' { Join-Path $env:LOCALAPPDATA 'nvim-data' }
    Set-CommandMock 'nvim' { $global:LASTEXITCODE = 0 }

    try {
        $output = Sync-LazyVim 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
        Set-FunctionMock 'Get-NeovimDataPath' $originalGetDataPath
    }

    Assert-False ($output -like '*LazyVim sync did not install*') 'installed directories should satisfy LazyVim sync verification'
}

function test_lazyvim_sync_uses_winget_neovim_fallback {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'Microsoft\WinGet\Links\nvim.exe'
    Assert-Contains $text 'Microsoft\WinGet\Packages'
    Assert-Contains $text 'Neovim\bin\nvim.exe'
    Assert-Contains $text '$env:ProgramFiles'
    Assert-Contains $text 'Get-ChildItem'
    Assert-Contains $text 'Get-NeovimCommand'
    Assert-Contains $text 'Get-NeovimDataPath'
    Assert-Contains $text 'vim.fn.stdpath'
    Assert-False ($text -like '*Join-Path $env:LOCALAPPDATA "nvim-data\lazy"*') 'sync verification should not hard-code Neovim data path'
}

function test_update_packages_syncs_lazyvim {
    $global:LazySynced = $false
    $lazySynced = $false
    $pulledScript = Join-Path $env:USERPROFILE 'dotfile.ps1'
    (Get-Content -Raw $script:DotfileScript) + @'

function Sync-LazyVim { $global:LazySynced = $true }
'@ | Set-Content -LiteralPath $pulledScript

    try {
        Invoke-UpdatedPackageInstall $pulledScript $true $false $false
        $lazySynced = $global:LazySynced
    } finally {
        Remove-Variable -Name LazySynced -Scope Global -ErrorAction SilentlyContinue
    }

    Assert-True $lazySynced 'updated package install should sync LazyVim'
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
