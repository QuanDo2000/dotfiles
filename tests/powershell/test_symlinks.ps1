# Symlink behavior tests. Most cover dry-run paths that don't touch the
# filesystem, plus one real symlink creation when privileges allow.

function TestSetup {
    Initialize-TestEnv | Out-Null
    # SetupSymlinks reads tracked sources from the repo and writes into the
    # isolated temp HOME. Pin DotfilesDir to the real repo so source lookups
    # resolve regardless of test-file ordering — other files leave the
    # module-scope $script:DotfilesDir pointing at their own (now-deleted) temp.
    $script:DotfilesDir = $script:RepoDir
}

function TestTeardown {
    Clear-TestEnv
}

function test_windows_neovim_bootstraps_lazy_without_tracking_lockfile {
    $lazyConfig = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/lua/config/lazy.lua')
    $gitignore = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/.gitignore')
    Assert-Contains $lazyConfig 'vim.fn.has("win32") == 1'
    Assert-Contains $lazyConfig 'https://github.com/folke/lazy.nvim.git'
    Assert-Contains $lazyConfig 'local lazy_spec = vim.fn.has("win32") == 1'
    Assert-Contains $lazyConfig '{ "folke/lazy.nvim" }'
    Assert-Contains $gitignore 'lazy-lock.json'
}

function test_windows_neovim_disables_fff_plugin {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/lua/plugins/fff.lua')
    Assert-Contains $config 'vim.fn.has("win32") == 1'
}

function test_windows_gitconfig_uses_platform_gpg_program {
    $shared = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\shared\.gitconfig')
    $windows = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\windows\.gitconfig')

    Assert-False ($shared -match '(?m)^\s*program\s*=\s*gpg\s*$') 'shared config must not override the platform GPG program'
    Assert-Contains $windows 'C:/Program Files/GnuPG/bin/gpg.exe'
}

function test_windows_neovim_links_stable_files_not_whole_directory {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $specs = @(Get-WindowsLinkSpecs)
    $nvimRoot = Join-Path $env:LOCALAPPDATA 'nvim'
    $nvimSpecs = @($specs | Where-Object { $_.Destination -like "$nvimRoot*" })

    Assert-False ([bool]($nvimSpecs | Where-Object { $_.Destination -eq $nvimRoot })) 'whole Neovim directory should not be linked'
    Assert-True ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'init.lua') })) 'init.lua should be linked'
    Assert-True ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'lua') })) 'lua directory should be linked'
    Assert-False ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'lazyvim.json') })) 'lazyvim.json should remain writable'
}

function test_migrate_windows_nvim_config_replaces_legacy_directory_link {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $legacySource = Join-Path $script:DotfilesDir 'config\shared\config\nvim'
    $destination = Join-Path $env:LOCALAPPDATA 'nvim'
    try {
        New-Item -ItemType SymbolicLink -Path $destination -Target $legacySource | Out-Null
    } catch {
        return
    }

    Migrate-WindowsNvimConfig

    $item = Get-Item -LiteralPath $destination -Force
    Assert-True $item.PSIsContainer 'migrated Neovim path should remain a directory'
    Assert-False ([bool]$item.LinkType) 'migrated Neovim directory should be writable'
}

function test_linkpath_file_dry_run_does_not_create_destination {
    $script:Dry = $true
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    LinkPath $src $dst

    Assert-False (Test-Path -LiteralPath $dst) 'dst should not exist in dry run'
}

function test_linkpath_file_creates_missing_parent_directory {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'missing\parent\dst.txt'
    'hello' | Set-Content -LiteralPath $src

    try {
        LinkPath $src $dst
    } catch {
        if ($_.Exception.Message -match 'privilege|Administrator') { return }
        throw
    }

    $item = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    Assert-True ($item -and $item.LinkType -eq 'SymbolicLink') 'dst should be a symlink when parent was missing'
}

function test_global_agents_file_is_not_linked_on_windows {
    $sources = @(Get-WindowsLinkSpecs | ForEach-Object Source)

    Assert-False (($sources -join "`n") -match 'ai[\\/]AGENTS\.md') 'global AGENTS.md should not be linked on Windows'
}

function test_linkpath_skips_when_already_linked {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    try {
        New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
    } catch {
        return  # no symlink privilege; skip
    }

    # Re-linking should be a no-op — existing link's Target matches source.
    LinkPath $src $dst

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals $src $item.Target
}
