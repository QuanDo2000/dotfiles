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
    Assert-Contains $gitignore 'lazy-lock.json'
}

function test_windows_neovim_disables_fff_plugin {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config/shared/config/nvim/lua/plugins/fff.lua')
    Assert-Contains $config 'vim.fn.has("win32") == 1'
}

function test_linkpath_file_dry_run_does_not_create_destination {
    $script:Dry = $true
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    LinkPath $src $dst

    Assert-False (Test-Path -LiteralPath $dst) 'dst should not exist in dry run'
}

function test_linkpath_directory_dry_run_does_not_create_destination {
    $script:Dry = $true
    $src = Join-Path $env:USERPROFILE 'srcdir'
    $dst = Join-Path $env:USERPROFILE 'dstdir'
    New-Item -ItemType Directory -Path $src | Out-Null

    LinkPath $src $dst $true

    Assert-False (Test-Path -LiteralPath $dst) 'dst dir should not exist in dry run'
}

function test_linkpath_file_creates_symlink_when_privileged {
    # Native symlink creation on Windows requires admin OR Developer Mode.
    # If neither is on, skip rather than fail — CI runs as admin.
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    try {
        LinkPath $src $dst
    } catch {
        if ($_.Exception.Message -match 'privilege|Administrator') { return }
        throw
    }

    $item = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    Assert-True ($item -and $item.LinkType -eq 'SymbolicLink') 'dst should be a symlink'
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

function test_setupsymlinks_dry_run_completes {
    # Dry run drives every branch (incl. the AI config + skills loops) without
    # touching the filesystem — LinkPath returns early when $Dry.
    $script:Dry = $true
    SetupSymlinks
    Assert-True $true 'SetupSymlinks dry run threw no exception'
}

function test_ai_config_sources_exist {
    # Guards against typos in the AI Src->Dst mapping: every tracked source the
    # Windows symlinker references must exist under config/shared/ai.
    $ai = Join-Path $script:DotfilesDir 'config\shared\ai'
    foreach ($rel in @(
        'claude\settings.json'
    )) {
        Assert-FileExists (Join-Path $ai $rel)
    }
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
