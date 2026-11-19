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
    $script:OriginalGetRexExecutable = (Get-Command Get-RexExecutable).ScriptBlock
    $script:OriginalGetRexPreviewInstallLocation = (Get-Command Get-RexPreviewInstallLocation).ScriptBlock
    Set-FunctionMock 'Get-RexExecutable' { 'mock-rex-executable' }
    $script:RexOldPath = $env:Path
}

function TestTeardown {
    foreach ($name in 'Get-Command', 'Get-Item', 'Get-Process', 'mock-rex-executable', 'winget') { Clear-CommandMock $name }
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
