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

function test_linkpath_lowercase_overwrite_does_not_authorize_next_conflict {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $first = Join-Path $env:USERPROFILE 'first.txt'
    $second = Join-Path $env:USERPROFILE 'second.txt'
    'new' | Set-Content -LiteralPath $src
    'first old' | Set-Content -LiteralPath $first
    'second old' | Set-Content -LiteralPath $second
    $script:PromptCount = 0
    $originalPrompt = (Get-Command PromptAction).ScriptBlock
    Set-CommandMock 'PromptAction' {
        $script:PromptCount++
        if ($script:PromptCount -eq 1) { return 'o' }
        return 's'
    }
    try {
        LinkPath $src $first
        LinkPath $src $second
        Assert-Equals 2 $script:PromptCount
        Assert-Equals $src (Get-Item -LiteralPath $first).Target
        Assert-Equals 'second old' (Get-Content -LiteralPath $second)
        Assert-False $script:OverwriteAll 'lowercase overwrite must not persist consent'
        Assert-False $script:SkipAll 'lowercase skip must not persist consent'
    } finally {
        Set-CommandMock 'PromptAction' $originalPrompt
    }
}

function test_promptaction_retries_invalid_input_and_preserves_case {
    $path = $script:DotfileScript.Replace("'", "''")
    $command = ". '$path' -NoMain; `$choice = PromptAction 'destination' 'source'; Write-Output ('CHOICE=' + `$choice)"
    $output = @('x', 'S') | pwsh -NoProfile -NonInteractive -Command $command 2>&1 | Out-String
    Assert-Equals 0 $LASTEXITCODE
    Assert-Contains $output 'Invalid choice'
    Assert-Contains $output '[c]ancel'
    Assert-Contains $output 'CHOICE=S'
}

function test_linkpath_cancel_preserves_conflicting_file {
    $src = Join-Path $env:USERPROFILE 'src.txt'
    $dst = Join-Path $env:USERPROFILE 'dst.txt'
    'new' | Set-Content -LiteralPath $src
    'old' | Set-Content -LiteralPath $dst
    $path = $script:DotfileScript.Replace("'", "''")
    $command = ". '$path' -NoMain; LinkPath '$($src.Replace("'", "''"))' '$($dst.Replace("'", "''"))'"
    $output = 'c' | pwsh -NoProfile -NonInteractive -Command $command 2>&1 | Out-String
    Assert-Equals 1 $LASTEXITCODE
    Assert-Contains $output 'Link setup cancelled'
    Assert-Equals 'old' (Get-Content -LiteralPath $dst)
    Assert-False (Test-Path -LiteralPath "$dst.bak") 'cancel must not back up or replace the conflict'
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
