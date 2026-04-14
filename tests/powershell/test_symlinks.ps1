# Symlink behavior tests. Most cover dry-run paths that don't touch the
# filesystem, plus one real symlink creation when privileges allow.

function TestSetup {
    Initialize-TestEnv | Out-Null
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
