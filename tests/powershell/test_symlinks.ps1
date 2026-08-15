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

function test_windows_terminal_does_not_elevate_every_profile {
    $settings = Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\Terminal\settings.json') | ConvertFrom-Json
    Assert-False ($settings.profiles.defaults.elevate -eq $true) 'Windows Terminal profiles should run unelevated by default'
}

function test_windows_neovim_bootstraps_lazy_at_reviewed_lock {
    $lazyConfig = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/init.lua')
    $lock = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/lazy-lock.json') | ConvertFrom-Json
    Assert-Contains $lazyConfig 'vim.fn.has("win32") == 1'
    Assert-Contains $lazyConfig 'https://github.com/folke/lazy.nvim.git'
    Assert-Contains $lazyConfig 'lazy-lock.json'
    Assert-Contains $lazyConfig '"checkout", "--force", commit'
    Assert-Contains $lazyConfig 'vim.env.DOTFILE_NVIM_SYNC == "1"'
    Assert-Contains $lazyConfig 'lazy.nvim is missing; run dotfile update'
    Assert-False ($lazyConfig -like '*--branch=stable*') 'lazy.nvim bootstrap should use reviewed commit'
    Assert-Equals '85c7ff3711b730b4030d03144f6db6375044ae82' $lock.'lazy.nvim'.commit
}

function test_windows_neovim_disables_fff_plugin {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/init.lua')
    Assert-Contains $config 'enabled = vim.fn.has("win32") ~= 1'
}

function test_windows_gitconfig_uses_platform_gpg_program {
    $shared = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\shared\.gitconfig')
    $windows = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\windows\.gitconfig')

    Assert-False ($shared -match '(?m)^\s*program\s*=\s*gpg\s*$') 'shared config must not override the platform GPG program'
    Assert-Contains $windows 'C:/Program Files/GnuPG/bin/gpg.exe'
}

function test_windows_gpg_agent_caches_passphrase_for_eight_hours {
    $oldAppData = $env:APPDATA
    try {
        $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
        $destination = Join-Path $env:APPDATA 'gnupg\gpg-agent.conf'
        $spec = Get-WindowsLinkSpecs | Where-Object Destination -eq $destination

        Assert-True ([bool]$spec) 'GPG agent config should target the Gpg4win home'
        if ($spec) {
            $config = Get-Content -Raw $spec.Source
            Assert-Contains $config 'default-cache-ttl 28800'
            Assert-Contains $config 'max-cache-ttl 86400'
        }
    } finally {
        $env:APPDATA = $oldAppData
    }
}

function test_setupsymlinks_reloads_gpg4win_agent {
    $setup = (Get-Command SetupSymlinks).Definition

    Assert-Contains $setup "Join-Path `$env:ProgramFiles 'GnuPG\bin\gpgconf.exe'"
    Assert-False ($setup -match '(?m)^\s*gpgconf --reload') 'must not reload Git bundled GnuPG from PATH'
}

function test_windows_neovim_links_stable_files_not_whole_directory {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $specs = @(Get-WindowsLinkSpecs)
    $nvimRoot = Join-Path $env:LOCALAPPDATA 'nvim'
    $nvimSpecs = @($specs | Where-Object { $_.Destination -like "$nvimRoot*" })

    Assert-False ([bool]($nvimSpecs | Where-Object { $_.Destination -eq $nvimRoot })) 'whole Neovim directory should not be linked'
    Assert-True ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'init.lua') })) 'init.lua should be linked'
    Assert-True ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'lua') })) 'lua directory should be linked'
    Assert-False ([bool]($nvimSpecs | Where-Object { $_.Destination -eq (Join-Path $nvimRoot 'lazy-lock.json') })) 'runtime-written plugin lock should remain writable'
}

function test_windows_notepadplusplus_links_stable_settings_and_themes {
    $oldAppData = $env:APPDATA
    try {
        $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
        $root = Join-Path $env:APPDATA 'Notepad++'
        $specs = @(Get-WindowsLinkSpecs | Where-Object { $_.Destination -like "$root*" })

        foreach ($name in 'contextMenu.xml', 'shortcuts.xml', 'themes\catppuccin-macchiato.xml', 'themes\DarkModeDefault.xml') {
            Assert-True ([bool]($specs | Where-Object Destination -eq (Join-Path $root $name))) "$name should be linked"
        }
        Assert-False ([bool]($specs | Where-Object Destination -eq (Join-Path $root 'themes'))) 'whole themes directory should remain writable'
        Assert-False ([bool]($specs | Where-Object Destination -eq (Join-Path $root 'config.xml'))) 'runtime-written config.xml should remain writable'
    } finally {
        $env:APPDATA = $oldAppData
    }
}

function test_sync_lazy_lock_seeds_writable_file {
    $oldDotfilesDir = $script:DotfilesDir
    try {
        $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
        $source = Join-Path $script:DotfilesDir 'config\shared\config\nvim\lazy-lock.json'
        $target = Join-Path $env:LOCALAPPDATA 'nvim\lazy-lock.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent), (Split-Path $target -Parent) | Out-Null
        '{"plugin":{"commit":"reviewed"}}' | Set-Content $source
        '{"plugin":{"commit":"stale"}}' | Set-Content $target

        Sync-LazyLock
        Assert-Contains (Get-Content -Raw $target) 'reviewed'

        '{"plugin":{"commit":"runtime"}}' | Set-Content $target
        Assert-False ([bool](Get-Item $target).LinkType) 'lazy-lock.json should be a regular writable file'
        Assert-Contains (Get-Content -Raw $source) 'reviewed'
        Assert-Contains (Get-Content -Raw $target) 'runtime'
    } finally {
        $script:DotfilesDir = $oldDotfilesDir
    }
}

function test_sync_notepadplusplus_config_seeds_writable_settings {
    $oldAppData = $env:APPDATA
    $oldDotfilesDir = $script:DotfilesDir
    try {
        $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
        $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
        $source = Join-Path $script:DotfilesDir 'config\windows\Notepad++\config.xml'
        New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent) | Out-Null
        '<NotepadPlus><GUIConfigs /></NotepadPlus>' | Set-Content $source

        Sync-NotepadPlusPlusConfig

        $target = Join-Path $env:APPDATA 'Notepad++\config.xml'
        Assert-FileExists $target
        Assert-Contains (Get-Content -Raw $target) '<GUIConfigs />'
        Assert-False ([bool](Get-Item $target).LinkType) 'Notepad++ config should be a regular file'
        Assert-False (Get-Item $target).IsReadOnly 'Notepad++ config should be writable'
    } finally {
        $script:DotfilesDir = $oldDotfilesDir
        $env:APPDATA = $oldAppData
    }
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

function test_linkpath_skip_all_preserves_existing_directory {
    $source = Join-Path $env:USERPROFILE 'source'
    $destination = Join-Path $env:USERPROFILE 'destination'
    New-Item -ItemType Directory -Force -Path $source, $destination | Out-Null
    'keep' | Set-Content -LiteralPath (Join-Path $destination 'sentinel.txt')
    $script:SkipAll = $true

    LinkPath $source $destination $true

    Assert-FileExists (Join-Path $destination 'sentinel.txt') 'SkipAll should preserve conflicting directory contents'
    Assert-False (Test-Path -LiteralPath "$destination.bak") 'SkipAll should not create a directory backup'
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
