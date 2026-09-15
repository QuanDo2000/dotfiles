function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:AnkiOriginalDir = $script:DotfilesDir
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'repo'
    $script:AnkiMocks = @{}
    foreach ($name in 'InstallPackages', 'InstallFiraCodeNerdFont', 'InstallAi', 'Sync-ObsidianSettings') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    Set-CommandMock 'Get-Process' { }
    $source = Join-Path $env:USERPROFILE 'source'
    New-Item -ItemType Directory -Path $source | Out-Null
    '# fixture' | Set-Content (Join-Path $source '__init__.py')
    $script:AnkiZip = Join-Path $env:USERPROFILE 'addon.zip'
    Compress-Archive -Path "$source/*" -DestinationPath $script:AnkiZip
    $script:AnkiDownloads = 0
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $script:AnkiDownloads++
        Copy-Item -LiteralPath $script:AnkiZip -Destination $OutFile
    }
    $script:AnkiPins = Join-Path $script:DotfilesDir 'config/windows/anki-addons.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $script:AnkiPins) | Out-Null
    ConvertTo-Json -Depth 10 -InputObject @(@{ id = '876946123'; name = 'Pass/Fail 2'; url = 'https://ankiweb.net/fixture'; sha256 = (Get-FileHash $script:AnkiZip).Hash; config = @{ good_button_name = 'Pass'; webCorsOriginList = @('http://localhost') }; files = @{ '__init__.py' = (Get-FileHash (Join-Path $source '__init__.py')).Hash } }) |
        Set-Content $script:AnkiPins
    $script:AnkiRoot = Join-Path $env:APPDATA 'Anki2/addons21'
}

function TestTeardown {
    foreach ($name in $script:AnkiMocks.Keys) { Set-FunctionMock $name $script:AnkiMocks[$name] }
    foreach ($name in 'Get-Process', 'Invoke-WebRequest', 'Move-Item', 'winget') { Clear-CommandMock $name }
    $script:DotfilesDir = $script:AnkiOriginalDir
    Clear-TestEnv
}

function test_anki_doctor_reports_settings_drift {
    InstallManagedPackages
    foreach ($name in 'Get-RequiredCommands', 'Get-InstalledWingetPackages', 'Get-WindowsLinkSpecs', 'Get-CodexHome') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
    }
    Set-FunctionMock 'Get-RequiredCommands' { @() }
    Set-FunctionMock 'Get-WindowsLinkSpecs' { @() }
    Set-FunctionMock 'Get-InstalledWingetPackages' { Get-WingetPackages }
    Set-FunctionMock 'Get-CodexHome' { Join-Path $env:USERPROFILE '.codex' }
    New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA/nvim", "$env:USERPROFILE/.codex" | Out-Null
    '' | Set-Content "$env:LOCALAPPDATA/nvim/init.lua"
    '' | Set-Content "$env:USERPROFILE/.codex/config.toml"
    Verify 6>&1 | Out-Null
    Assert-False $script:VerifyFailed
    $metaPath = "$script:AnkiRoot/876946123/meta.json"
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
    $meta.config.good_button_name = 'unexpected'
    $meta | ConvertTo-Json -Depth 10 | Set-Content $metaPath
    $output = Verify 6>&1 | Out-String
    Assert-True $script:VerifyFailed 'doctor must fail on Anki settings drift'
    Assert-Contains $output 'good_button_name'
    InstallManagedPackages
    '# changed code' | Set-Content "$script:AnkiRoot/876946123/__init__.py"
    $output = Verify 6>&1 | Out-String
    Assert-True $script:VerifyFailed 'doctor must fail on Anki code drift'
    Assert-Contains $output 'file hash differs'
    InstallManagedPackages
    Verify 6>&1 | Out-Null
    Assert-False $script:VerifyFailed
}

function test_anki_pin_refresher {
    $python = Get-Command py, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { Skip-Test 'Python unavailable'; return }
    & $python.Source (Join-Path $script:RepoDir 'tests/python/test_anki_pins.py')
    Assert-Equals 0 $LASTEXITCODE
}

function test_anki_is_a_managed_winget_package {
    Assert-True (@(Get-WingetPackages) -contains 'Anki.Anki')
}

function test_managed_packages_install_anki_addons {
    InstallManagedPackages
    Assert-FileExists (Join-Path $script:AnkiRoot '876946123/__init__.py')
}

function test_anki_addons_preserve_existing_data {
    $addon = Join-Path $script:AnkiRoot '876946123'
    New-Item -ItemType Directory -Force -Path "$addon/user_files", "$script:AnkiRoot/other" | Out-Null
    'keep' | Set-Content "$addon/user_files/data.txt"
    'old' | Set-Content "$addon/old.py"
    'unrelated' | Set-Content "$script:AnkiRoot/other/__init__.py"
    '{"config":{"custom":42,"good_button_name":"Good","apiKey":"local-test-secret"},"disabled":true}' | Set-Content "$addon/meta.json"
    InstallManagedPackages
    Assert-FileExists "$addon/__init__.py"
    Assert-Equals 'keep' (Get-Content "$addon/user_files/data.txt")
    Assert-Equals 'unrelated' (Get-Content "$script:AnkiRoot/other/__init__.py")
    $meta = Get-Content "$addon/meta.json" -Raw | ConvertFrom-Json
    Assert-Equals 'Pass' $meta.config.good_button_name
    Assert-Equals 42 $meta.config.custom
    Assert-Equals 'local-test-secret' $meta.config.apiKey
    Assert-False $meta.disabled
    Assert-False $meta.update_enabled
    Assert-False (Test-Path "$addon/old.py")
    Assert-Equals 1 @(Get-ChildItem (Join-Path $env:APPDATA 'Anki2/dotfile-addons-backups') -Recurse -Filter old.py).Count
    InstallManagedPackages
    Assert-Equals 1 $script:AnkiDownloads
}

function test_anki_addons_dry_run_is_read_only {
    $script:Dry = $true
    InstallManagedPackages
    Assert-Equals 0 $script:AnkiDownloads
    Assert-False (Test-Path $script:AnkiRoot)
}

function test_anki_addons_refuse_running_anki {
    Set-CommandMock 'Get-Process' { @{ ProcessName = 'anki' } }
    Assert-Throws { InstallManagedPackages }
    Assert-Equals 0 $script:AnkiDownloads
    Assert-False (Test-Path $script:AnkiRoot)
}

function test_anki_update_installs_managed_addons {
    foreach ($name in 'SetupSymlinks', 'Sync-NeovimPlugins', 'Assert-WindowsHealthy') {
        $script:AnkiMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    Update-Packages '' -AfterRepoUpdate
    Assert-FileExists "$script:AnkiRoot/876946123/__init__.py"
}

function test_anki_winget_refuses_running_anki {
    Set-CommandMock 'Get-Process' { @{ ProcessName = 'anki' } }
    $script:AnkiWingetCalled = $false
    Set-CommandMock 'winget' { $script:AnkiWingetCalled = $true }
    Assert-Throws { Invoke-Winget 'failed' @('upgrade', '--id', 'Anki.Anki', '--exact') }
    Assert-False $script:AnkiWingetCalled
}

function test_anki_addons_roll_back_failed_activation {
    $addon = Join-Path $script:AnkiRoot '876946123'
    New-Item -ItemType Directory -Force -Path $addon | Out-Null
    'original' | Set-Content "$addon/__init__.py"
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, $ErrorAction)
        if ((Split-Path $LiteralPath -Leaf) -eq 'addon') { throw 'activation failed' }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -ErrorAction Stop
    }
    Assert-Throws { InstallManagedPackages }
    Assert-Equals 'original' (Get-Content "$addon/__init__.py")
}

function test_anki_addons_reject_hash_mismatch {
    Add-Content $script:AnkiZip 'tampered'
    Assert-Throws { InstallManagedPackages }
    Assert-False (Test-Path "$script:AnkiRoot/876946123")
}

function test_anki_addons_reject_archive_traversal {
    $zip = [IO.Compression.ZipFile]::Open($script:AnkiZip, 'Update')
    try { $null = $zip.CreateEntry('../escape.py') } finally { $zip.Dispose() }
    $pins = Get-Content $script:AnkiPins -Raw | ConvertFrom-Json
    @($pins)[0].sha256 = (Get-FileHash $script:AnkiZip).Hash
    ConvertTo-Json -InputObject @($pins) -Depth 10 | Set-Content $script:AnkiPins
    Assert-Throws { InstallManagedPackages }
    Assert-False (Test-Path "$script:AnkiRoot/876946123")
}
