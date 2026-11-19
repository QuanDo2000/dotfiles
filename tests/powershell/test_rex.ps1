function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:RexCalls = [System.Collections.Generic.List[string]]::new()
    $script:SourceExit = 0
    $script:UpgradeExit = -1978335189
    $script:ListExit = -1978335212
    $script:SourceUrl = 'https://pkgs.superlogical.com/rex/winget'
    $script:SourceExplicit = $true
    Set-CommandMock 'winget' {
        $script:RexCalls.Add($args -join ' ')
        $global:LASTEXITCODE = switch ($args[0]) {
            source { $script:SourceExit }
            list { $script:ListExit }
            install { 0 }
            upgrade { $script:UpgradeExit }
            default { throw "Unexpected WinGet verb: $($args[0])" }
        }
        if ($args[0] -eq 'source' -and $LASTEXITCODE -eq 0) {
            @{ Name = 'rex'; Arg = $script:SourceUrl; Explicit = $script:SourceExplicit; Type = 'Microsoft.Rest' } | ConvertTo-Json -Compress
        }
    }
    Set-CommandMock 'mock-rex-executable' { $script:RexCalls.Add("rex.exe $($args -join ' ')"); $global:LASTEXITCODE = 0 }
    Set-CommandMock 'Get-Process' { return $null }
    $script:OriginalGetFileSha256 = (Get-Command Get-FileSha256).ScriptBlock
    $script:OriginalGetRexExecutable = (Get-Command Get-RexExecutable).ScriptBlock
    $script:OriginalGetRexPreviewInstallLocation = (Get-Command Get-RexPreviewInstallLocation).ScriptBlock
    Set-FunctionMock 'Get-RexExecutable' { 'mock-rex-executable' }
    $script:RexOldPath = $env:Path
}

function TestTeardown {
    foreach ($name in 'Get-Command', 'Get-Item', 'Get-Process', 'mock-rex-executable', 'winget') { Clear-CommandMock $name }
    Set-FunctionMock 'Get-FileSha256' $script:OriginalGetFileSha256
    Set-FunctionMock 'Get-RexExecutable' $script:OriginalGetRexExecutable
    Set-FunctionMock 'Get-RexPreviewInstallLocation' $script:OriginalGetRexPreviewInstallLocation
    $env:Path = $script:RexOldPath
    Clear-TestEnv
}

function test_rex_preview_is_installed_and_upgraded_only_from_the_official_source {
    Sync-RexPackage
    $flags = '--id Superlogical.RexServer.Preview --exact --source rex --scope user'
    Assert-Equals "list $flags --disable-interactivity --accept-source-agreements" $script:RexCalls[1]
    Assert-Equals "install $flags --disable-interactivity --accept-package-agreements --accept-source-agreements" $script:RexCalls[2]
    Assert-Equals 'rex.exe --autostart=false skill setup --agent pi' $script:RexCalls[3]

    $script:RexCalls.Clear()
    $script:ListExit = 0
    Sync-RexPackage -Update
    Assert-Equals "upgrade $flags --disable-interactivity --accept-package-agreements --accept-source-agreements" $script:RexCalls[2]

    $script:RexCalls.Clear()
    Clear-CommandMock 'Get-Process'
    Set-CommandMock 'Get-Process' { @{ Name = 'rex' } }
    Sync-RexPackage -Update
    Assert-Equals 'rex.exe --autostart=false skill setup --agent pi' $script:RexCalls[2]
    Assert-Equals 3 $script:RexCalls.Count
}

function test_rex_preview_skips_missing_source_and_never_uses_a_lookalike_source {
    $script:SourceExit = -1978335214
    Sync-RexPackage
    Assert-Equals @('source export --name rex --disable-interactivity') $script:RexCalls.ToArray()

    $script:RexCalls.Clear()
    $script:SourceExit = 0
    $script:SourceUrl = 'https://example.invalid/winget'
    $output = Sync-RexPackage 6>&1 | Out-String
    Assert-Contains $output 'does not match the official explicit source'
    Assert-Equals 1 $script:RexCalls.Count

    $script:RexCalls.Clear()
    $script:Dry = $true
    Sync-RexPackage -Update
    Assert-Equals 0 $script:RexCalls.Count
}

function test_rex_executable_rejects_standalone_rex_on_path {
    Set-CommandMock 'Get-Command' {
        param($Name, $CommandType, $ErrorAction)
        if ($Name -eq 'rex.exe' -and $CommandType -eq 'Application') { return @{ Source = $script:RexPath } }
        Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    $script:RexTarget = $null
    Set-CommandMock 'Get-Item' {
        param($LiteralPath, [switch]$Force)
        if ($LiteralPath -eq $script:RexPath) {
            if ($script:RexTarget) { return @{ LinkType = 'SymbolicLink'; Target = @($script:RexTarget) } }
            return @{ LinkType = $null }
        }
        Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
    }
    $script:RexInstallLocation = Join-Path $env:LOCALAPPDATA 'custom-portable-root/Superlogical.RexServer.Preview_source'
    Set-FunctionMock 'Get-RexPreviewInstallLocation' { $script:RexInstallLocation }
    $script:RexPath = Join-Path $env:LOCALAPPDATA 'old-portable-root/Superlogical.RexServer.Preview_source/rex.exe'
    Assert-Throws { & $script:OriginalGetRexExecutable } 'do not run a stale Rex executable even with a matching package directory name'
    $script:RexPath = Join-Path $script:RexInstallLocation 'rex.exe'
    Assert-Equals $script:RexPath (& $script:OriginalGetRexExecutable)
    $script:RexTarget = $script:RexPath
    $script:RexPath = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/rex.exe'
    Assert-Equals $script:RexTarget (& $script:OriginalGetRexExecutable)
}

function test_failed_rex_upgrade_leaves_skill_setup_for_the_next_run {
    $script:ListExit = 0
    $script:UpgradeExit = -1978335215
    Assert-Throws { Sync-RexPackage -Update } 'report the Rex upgrade failure to the caller'
    Assert-Equals 3 $script:RexCalls.Count
}

function test_rex_desktop_sync_while_running_preserves_unmanaged_settings_and_is_idempotent {
    $root = Join-Path $env:LOCALAPPDATA 'Superlogical\Rex'
    $ini = Join-Path $root 'config.ini'
    Sync-RexDesktopAppearance
    Assert-False (Test-Path -LiteralPath $root) 'do not seed desktop settings on a server-only machine'
    New-Item -ItemType Directory -Path $root | Out-Null
    New-Item -ItemType File -Path (Join-Path $root 'rex.exe') | Out-Null
    $original = "# Keep comment`r`ntab_placement = above`r`n[client]`r`nremote_control = false`r`n[palettes.private]`r`nfont_size = unrelated`r`n[]`r`nfont_family = Cascadia Mono`r`n"
    [IO.File]::WriteAllText($ini, $original)
    $script:Dry = $true
    Sync-RexDesktopAppearance
    Assert-Equals $original ([IO.File]::ReadAllText($ini))
    $script:Dry = $false
    Set-CommandMock 'Get-Process' { @{ Name = 'rex' } }
    Sync-RexDesktopAppearance
    $current = [IO.File]::ReadAllText($ini)
    Assert-Contains $current "# Keep comment`r`ntab_placement = left`r`n[client]`r`nremote_control = false`r`n[palettes.private]`r`nfont_size = unrelated`r`n[]`r`nfont_family = FiraCode Nerd Font`r`n"
    Assert-Contains $current "dark_theme_color_palette = dotfiles_macchiato`r`n"
    Assert-Contains $current "[palettes.dotfiles_macchiato]`r`n"
    Assert-Contains $current 'background = #24273a'
    $backups = @(Get-ChildItem -LiteralPath $root -Filter 'config.ini.backup.*')
    Assert-Equals 1 $backups.Count
    Assert-Equals $original ([IO.File]::ReadAllText($backups[0].FullName))
    Sync-RexDesktopAppearance
    Assert-Equals $current ([IO.File]::ReadAllText($ini))
    Assert-Equals 1 @(Get-ChildItem -LiteralPath $root -Filter 'config.ini.backup.*').Count

    $unmanaged = "`r`n# Preserve this comment`r`n[server]`r`ntailscale_enabled = false`r`n"
    [IO.File]::WriteAllText($ini, $current.Replace('background = #24273a', 'background = #000000') + $unmanaged)
    Sync-RexDesktopAppearance
    Assert-Equals ($current + $unmanaged) ([IO.File]::ReadAllText($ini))
}

function test_rex_desktop_sync_preserves_an_edit_during_preflight {
    $root = Join-Path $env:LOCALAPPDATA 'Superlogical\Rex'
    New-Item -ItemType Directory -Path $root | Out-Null
    New-Item -ItemType File -Path (Join-Path $root 'rex.exe') | Out-Null
    $script:RexIni = Join-Path $root 'config.ini'
    # These edits compare equal under culture-sensitive Unicode comparison.
    $start = "tab_placement = above`n# $([char]0x00e9)`n"
    $script:RexConcurrentEdit = "tab_placement = above`n# e$([char]0x0301)`n"
    [IO.File]::WriteAllText($script:RexIni, $start)
    Set-FunctionMock 'Get-FileSha256' {
        param($Path)
        if ($Path -eq $script:RexIni) {
            [IO.File]::WriteAllText($Path, $script:RexConcurrentEdit)
        }
        & $script:OriginalGetFileSha256 $Path
    }
    Assert-Throws { Sync-RexDesktopAppearance } 'concurrent sync must report a conflict'
    Assert-True ([string]::Equals($script:RexConcurrentEdit, [IO.File]::ReadAllText($script:RexIni), [StringComparison]::Ordinal)) 'preserve the exact editor change'
    Assert-Equals 0 @(Get-ChildItem -LiteralPath $root -Filter 'config.ini.backup.*').Count
}

function test_rex_links_only_the_two_shared_assets_into_roaming_appdata {
    $root = Join-Path $env:APPDATA 'rex'
    $specs = @(Get-WindowsLinkSpecs | Where-Object { $_.Destination -like "$root*" })
    Assert-Equals 2 $specs.Count
    foreach ($name in 'init.lua', 'Catppuccin Macchiato.conf') {
        $spec = $specs | Where-Object Destination -eq (Join-Path $root $name)
        Assert-Equals 'File' $spec.Kind
        Assert-Equals (Join-Path $script:RepoDir "config\rex\$name") $spec.Source
        Assert-FileExists $spec.Source
    }
}
