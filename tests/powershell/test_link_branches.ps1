# Exercise non-trivial branches of LinkPath: overwrite-all, backup-all,
# skip-all, and force-replace of a real directory.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:Quiet = $true
}

function TestTeardown {
    Clear-TestEnv
}

function test_symlink_probe_does_not_hide_unrelated_failures {
    Set-CommandMock 'New-Item' { throw [IO.IOException]::new('disk full') }
    try {
        Assert-Throws { Try-Skip-If-No-Symlink-Privilege } 'unrelated filesystem failure must surface'
    } finally {
        Clear-CommandMock 'New-Item'
    }
}

function test_getlinkconflict_finds_item_when_testpath_reports_false {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'old' | Set-Content -LiteralPath $dst
    Set-CommandMock 'Test-Path' { $false }
    try {
        $conflict = Get-LinkConflict $src $dst
        Assert-True ($null -ne $conflict) 'Get-LinkConflict should trust Get-Item for dangling-link compatibility'
    } finally {
        Clear-CommandMock 'Test-Path'
    }
}

function test_linkpath_file_overwrite_all_replaces_existing {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:OverwriteAll = $true

    LinkPath $src $dst

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
    Assert-Equals $src $item.Target
}

function test_linkpath_file_backup_all_renames_existing {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:BackupAll = $true

    LinkPath $src $dst

    Assert-FileExists "$dst.bak"
    Assert-Equals 'old' ((Get-Content -LiteralPath "$dst.bak") -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
}

function test_linkpath_file_backup_preserves_existing_backup {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'current' | Set-Content -LiteralPath $dst
    'existing backup' | Set-Content -LiteralPath "$dst.bak"
    $script:BackupAll = $true

    LinkPath $src $dst

    Assert-Equals 'existing backup' ((Get-Content -LiteralPath "$dst.bak") -join '')
    Assert-Equals 'current' ((Get-Content -LiteralPath "$dst.bak.1") -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals $src $item.Target
}

function test_linkpath_file_backup_preserves_dangling_link {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $missing = Join-Path $env:USERPROFILE 'missing.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    New-Item -ItemType SymbolicLink -Path $dst -Target $missing | Out-Null
    $script:BackupAll = $true

    LinkPath $src $dst

    $backup = Get-Item -LiteralPath "$dst.bak" -Force
    Assert-Equals 'SymbolicLink' $backup.LinkType
    Assert-Equals $missing $backup.Target
    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals $src $item.Target
}

function test_linkpath_file_backup_treats_brackets_literally {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst[1].txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:BackupAll = $true

    LinkPath $src $dst

    Assert-Equals 'old' ((Get-Content -LiteralPath "$dst.bak") -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
}

function test_linkpath_file_skip_all_leaves_existing_untouched {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $script:SkipAll = $true

    LinkPath $src $dst

    Assert-Equals 'old' ((Get-Content -LiteralPath $dst) -join '')
    $item = Get-Item -LiteralPath $dst -Force
    Assert-False ($item.LinkType -eq 'SymbolicLink') 'dst should remain a regular file'
}

function test_linkpath_directory_force_replaces_existing_directory {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'srcdir'
    $dst = Join-Path $env:USERPROFILE 'dstdir'
    New-Item -ItemType Directory -Path $src | Out-Null
    New-Item -ItemType Directory -Path $dst | Out-Null
    'data' | Set-Content -LiteralPath (Join-Path $dst 'preexisting.txt')
    $script:Force = $true

    LinkPath $src $dst $true

    $item = Get-Item -LiteralPath $dst -Force
    Assert-Equals 'SymbolicLink' $item.LinkType
    Assert-Equals $src $item.Target
}
