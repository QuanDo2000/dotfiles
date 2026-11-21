function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:AnkiOriginalDir = $script:DotfilesDir
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'repo'
    $script:AnkiMocks = @{}
    foreach ($name in 'InstallPackages', 'Sync-RexPackage', 'Test-RexWingetSource', 'InstallFiraCodeNerdFont', 'InstallAi', 'Sync-ObsidianSettings') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    Set-CommandMock 'Get-Process' { }
    Set-CommandMock 'Invoke-WebRequest' { throw 'Dotfiles must not download Anki add-ons' }
    $manifest = Join-Path $script:DotfilesDir 'config/windows/anki-addons.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $manifest) | Out-Null
    '[{"id":"876946123","name":"Pass/Fail 2","config":{"good_button_name":"Pass"}}]' | Set-Content $manifest
    $script:AnkiRoot = Join-Path $env:APPDATA 'Anki2/addons21'
    $script:AnkiAddon = Join-Path $script:AnkiRoot '876946123'
}

function TestTeardown {
    foreach ($name in $script:AnkiMocks.Keys) { Set-FunctionMock $name $script:AnkiMocks[$name] }
    foreach ($name in 'Get-Process', 'Invoke-WebRequest', 'winget') { Clear-CommandMock $name }
    $script:DotfilesDir = $script:AnkiOriginalDir
    Clear-TestEnv
}

function test_anki_doctor_reports_settings_but_not_code_drift {
    New-Item -ItemType Directory -Path $script:AnkiAddon -Force | Out-Null
    '# changed by Anki' | Set-Content "$script:AnkiAddon/__init__.py"
    $metaPath = Join-Path $script:AnkiAddon 'meta.json'
    '{"config":{"good_button_name":"unexpected"}}' | Set-Content $metaPath
    foreach ($name in 'Get-RequiredCommands', 'Get-InstalledWingetPackages', 'Get-WindowsLinkSpecs') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
    }
    Set-FunctionMock 'Get-RequiredCommands' { @() }
    Set-FunctionMock 'Get-WindowsLinkSpecs' { @() }
    Set-FunctionMock 'Get-InstalledWingetPackages' { Get-WingetPackages }
    New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA/nvim" | Out-Null
    '' | Set-Content "$env:LOCALAPPDATA/nvim/init.lua"
    $output = Verify 6>&1 | Out-String
    Assert-True $script:VerifyFailed 'doctor must fail on Anki settings drift'
    Assert-Contains $output 'good_button_name'
    InstallManagedPackages
    Verify 6>&1 | Out-Null
    Assert-False $script:VerifyFailed
}

function test_anki_update_preserves_code_and_migrates_legacy_update_lock {
    foreach ($name in 'SetupSymlinks', 'Sync-NeovimPlugins', 'Assert-WindowsHealthy') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    New-Item -ItemType Directory -Force -Path "$script:AnkiAddon/user_files", "$script:AnkiRoot/other" | Out-Null
    '# installed version' | Set-Content "$script:AnkiAddon/__init__.py"
    'keep' | Set-Content "$script:AnkiAddon/user_files/data.txt"
    'unrelated' | Set-Content "$script:AnkiRoot/other/__init__.py"
    $metaPath = Join-Path $script:AnkiAddon 'meta.json'
    '{"config":{"custom":42,"good_button_name":"Good","apiKey":"local-test-secret"},"disabled":true,"update_enabled":false,"dotfile_sha256":"legacy","mod":12345,"branch_index":2}' | Set-Content $metaPath
    Update-Packages '' -AfterRepoUpdate
    Assert-Equals '# installed version' (Get-Content "$script:AnkiAddon/__init__.py")
    Assert-Equals 'keep' (Get-Content "$script:AnkiAddon/user_files/data.txt")
    Assert-Equals 'unrelated' (Get-Content "$script:AnkiRoot/other/__init__.py")
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
    Assert-Equals 'Pass' $meta.config.good_button_name
    Assert-Equals 42 $meta.config.custom
    Assert-Equals 'local-test-secret' $meta.config.apiKey
    Assert-False $meta.disabled
    Assert-True $meta.update_enabled
    Assert-False ($null -ne $meta.PSObject.Properties['dotfile_sha256'])
    Assert-Equals 12345 $meta.mod
    Assert-Equals 2 $meta.branch_index
    # A later choice made in Anki no longer belongs to dotfiles.
    $meta.update_enabled = $false
    $meta | ConvertTo-Json -Depth 10 | Set-Content $metaPath
    InstallManagedPackages
    Assert-False (Get-Content $metaPath -Raw | ConvertFrom-Json).update_enabled
}

function test_anki_missing_addon_reports_native_install_code {
    $message = try { InstallManagedPackages; '' } catch { $_.Exception.Message }
    Assert-Contains $message 'Tools > Add-ons > Get Add-ons'
    Assert-Contains $message '876946123'
    Assert-False (Test-Path $script:AnkiRoot)

    foreach ($name in 'SetupSymlinks', 'Sync-NeovimPlugins', 'Assert-WindowsHealthy') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    $script:AnkiUpdateReachedEditor = $false
    Set-FunctionMock 'Sync-NeovimPlugins' { $script:AnkiUpdateReachedEditor = $true }
    Set-FunctionMock 'Sync-RexPackage' { throw 'Rex Preview setup failed' }
    $message = try { Update-Packages '' -AfterRepoUpdate; '' } catch { $_.Exception.Message }
    Assert-True $script:AnkiUpdateReachedEditor 'a missing add-on must not stop unrelated updates'
    Assert-Contains $message 'Rex Preview setup failed'
    Assert-Contains $message '876946123'
}

function test_anki_addons_dry_run_is_read_only {
    $script:Dry = $true
    InstallManagedPackages
    Assert-False (Test-Path $script:AnkiRoot)
}

function test_anki_addons_refuse_running_anki {
    Set-CommandMock 'Get-Process' { @{ ProcessName = 'anki' } }
    Assert-Throws { InstallManagedPackages }
    Assert-False (Test-Path $script:AnkiRoot)
}

function test_anki_winget_refuses_running_anki {
    Assert-True (@(Get-WingetPackages) -contains 'Anki.Anki')
    Set-CommandMock 'Get-Process' { @{ ProcessName = 'anki' } }
    $script:AnkiWingetCalled = $false
    Set-CommandMock 'winget' { $script:AnkiWingetCalled = $true }
    Assert-Throws { Invoke-Winget 'failed' @('upgrade', '--id', 'Anki.Anki', '--exact') }
    Assert-False $script:AnkiWingetCalled
}
