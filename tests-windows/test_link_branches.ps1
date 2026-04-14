# Exercise non-trivial branches of LinkFile / LinkDir: overwrite-all,
# backup-all, skip-all, and LinkDir force-replace of a real directory.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:Quiet = $true
}

function TestTeardown {
    Clear-TestEnv
}

function Try-Skip-If-No-Symlink-Privilege {
    # Create a throwaway symlink to detect privilege; return $true if unavailable.
    $probeSrc = Join-Path $env:USERPROFILE 'probe_src'
    $probeDst = Join-Path $env:USERPROFILE 'probe_dst'
    'x' | Set-Content -LiteralPath $probeSrc
    try {
        New-Item -ItemType SymbolicLink -Path $probeDst -Target $probeSrc -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probeDst -Force
        return $false
    } catch {
        return $true
    }
}

function test_linkfile_overwrite_all_replaces_existing {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:OverwriteAll = $true

    LinkFile $src $dst

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
    Assert-Equals $src $item.Target
}

function test_linkfile_backup_all_renames_existing {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:BackupAll = $true

    LinkFile $src $dst

    Assert-FileExists "$dst.bak"
    Assert-Equals 'old' ((Get-Content -LiteralPath "$dst.bak") -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
}

function test_linkfile_skip_all_leaves_existing_untouched {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:SkipAll = $true

    LinkFile $src $dst

    Assert-Equals 'old' ((Get-Content -LiteralPath $dst) -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-False ($item.LinkType -eq 'SymbolicLink') 'dst should remain a regular file'
}

function test_linkdir_force_replaces_existing_directory {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'srcdir'
    $dst = Join-Path $env:USERPROFILE 'dstdir'
    New-Item -ItemType Directory -Path $src | Out-Null
    New-Item -ItemType Directory -Path $dst | Out-Null
    'data' | Set-Content -LiteralPath (Join-Path $dst 'preexisting.txt')
    $script:Force = $true

    LinkDir $src $dst

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
    Assert-Equals $src $item.Target
}
