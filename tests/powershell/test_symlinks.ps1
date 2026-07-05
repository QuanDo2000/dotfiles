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

function test_linkfile_dry_run_does_not_create_destination {
    $script:Dry = $true
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    LinkFile $src $dst

    Assert-False (Test-Path -LiteralPath $dst) 'dst should not exist in dry run'
}

function test_linkdir_dry_run_does_not_create_destination {
    $script:Dry = $true
    $src = Join-Path $env:USERPROFILE 'srcdir'
    $dst = Join-Path $env:USERPROFILE 'dstdir'
    New-Item -ItemType Directory -Path $src | Out-Null

    LinkDir $src $dst

    Assert-False (Test-Path -LiteralPath $dst) 'dst dir should not exist in dry run'
}

function test_linkfile_creates_symlink_when_privileged {
    # Native symlink creation on Windows requires admin OR Developer Mode.
    # If neither is on, skip rather than fail — CI runs as admin.
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    try {
        LinkFile $src $dst
    } catch {
        if ($_.Exception.Message -match 'privilege|Administrator') { return }
        throw
    }

    $item = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    Assert-True ($item -and $item.LinkType -eq 'SymbolicLink') 'dst should be a symlink'
}

function test_setupsymlinks_dry_run_completes {
    # Dry run drives every branch (incl. the AI config + skills loops) without
    # touching the filesystem — LinkFile/LinkDir return early when $Dry.
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

function test_linkfile_skips_when_already_linked {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'hello' | Set-Content -LiteralPath $src

    try {
        New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
    } catch {
        return  # no symlink privilege; skip
    }

    # Re-linking should be a no-op — existing link's Target matches source.
    LinkFile $src $dst

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals $src $item.Target
}
