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
    $script:Dry = $false
    $script:LazySynced = $false
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    $originalInstallExtras = (Get-Command InstallExtras).ScriptBlock
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalSyncLazyVimConfig = (Get-Command Sync-LazyVimConfig).ScriptBlock
    $originalSyncLazyVim = (Get-Command Sync-LazyVim).ScriptBlock
    $originalAssertWindowsHealthy = if (Get-Command Assert-WindowsHealthy -ErrorAction SilentlyContinue) {
        (Get-Command Assert-WindowsHealthy).ScriptBlock
    } else { $null }
    Set-FunctionMock 'InstallExtras' { }
    Set-FunctionMock 'InstallAi' { }
    Set-FunctionMock 'Sync-LazyVimConfig' { }
    Set-FunctionMock 'Sync-LazyVim' { $script:LazySynced = $true }
    Set-FunctionMock 'Assert-WindowsHealthy' { }

    try {
        Update-Packages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'InstallExtras' $originalInstallExtras
        Set-FunctionMock 'InstallAi' $originalInstallAi
        Set-FunctionMock 'Sync-LazyVimConfig' $originalSyncLazyVimConfig
        Set-FunctionMock 'Sync-LazyVim' $originalSyncLazyVim
        if ($originalAssertWindowsHealthy) {
            Set-FunctionMock 'Assert-WindowsHealthy' $originalAssertWindowsHealthy
        } else {
            Remove-Item function:\Assert-WindowsHealthy -ErrorAction SilentlyContinue
        }
    }

    Assert-True $script:LazySynced 'Update-Packages should sync LazyVim'
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
