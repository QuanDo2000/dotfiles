function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:ObsidianOriginalDir = $script:DotfilesDir
    $script:ObsidianOriginalVault = $env:DOTFILE_OBSIDIAN_VAULT
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'repo'
    $env:DOTFILE_OBSIDIAN_VAULT = Join-Path $env:USERPROFILE 'vault'
    New-Item -ItemType Directory -Force -Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian" | Out-Null
    $script:ObsidianMocks = @{}
    foreach ($name in 'InstallPackages', 'InstallFiraCodeNerdFont', 'InstallAi', 'InstallAnkiAddons') {
        $script:ObsidianMocks[$name] = (Get-Command $name).ScriptBlock
        Set-FunctionMock $name { }
    }
    Set-CommandMock 'Get-Process' { }
    New-Item -ItemType Directory -Force -Path "$script:DotfilesDir/config/shared", "$script:DotfilesDir/config/windows" | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoDir 'config/shared/obsidian') -Destination "$script:DotfilesDir/config/shared/obsidian" -Recurse -Force
}

function TestTeardown {
    foreach ($name in $script:ObsidianMocks.Keys) { Set-FunctionMock $name $script:ObsidianMocks[$name] }
    Clear-CommandMock 'Get-Process'
    $script:DotfilesDir = $script:ObsidianOriginalDir
    $env:DOTFILE_OBSIDIAN_VAULT = $script:ObsidianOriginalVault
    Clear-TestEnv
}

function test_obsidian_vault_selection_requires_unambiguous_registration {
    $expected = $env:DOTFILE_OBSIDIAN_VAULT
    $env:DOTFILE_OBSIDIAN_VAULT = $null
    $registry = Join-Path $env:APPDATA 'obsidian/obsidian.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $registry) | Out-Null
    @{ vaults = @{ first = @{ path = $expected } } } | ConvertTo-Json -Depth 5 | Set-Content $registry
    Assert-Equals $expected (Get-ObsidianVaultPath)
    @{ vaults = @{ first = @{ path = $expected }; second = @{ path = $expected } } } | ConvertTo-Json -Depth 5 | Set-Content $registry
    Assert-Throws { Get-ObsidianVaultPath }
}

function test_obsidian_validates_all_sources_before_writing {
    '{broken' | Set-Content "$script:DotfilesDir/config/shared/obsidian/templates.json"
    Assert-Throws { InstallManagedPackages }
    Assert-False (Test-Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json")
}

function test_obsidian_refuses_linked_settings {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $external = Join-Path $env:USERPROFILE 'external.json'
    '{}' | Set-Content $external
    New-Item -ItemType SymbolicLink -Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json" -Target $external | Out-Null
    Assert-Throws { InstallManagedPackages }
    Assert-Equals '{}' (Get-Content $external)
}

function test_obsidian_is_managed {
    Assert-True (@(Get-WingetPackages) -contains 'Obsidian.Obsidian')
}

function test_obsidian_installs_only_selected_settings {
    '{"layout":"keep"}' | Set-Content "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/workspace.json"
    'keep note' | Set-Content "$env:DOTFILE_OBSIDIAN_VAULT/note.md"
    InstallManagedPackages
    Assert-FileExists "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/hotkeys.json"
    Assert-Equals 'keep note' (Get-Content "$env:DOTFILE_OBSIDIAN_VAULT/note.md")
    Assert-Equals '{"layout":"keep"}' (Get-Content "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/workspace.json")
}

function test_obsidian_dry_run_does_not_write {
    $script:Dry = $true
    InstallManagedPackages
    Assert-False (Test-Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json")
}

function test_obsidian_requires_closed_app {
    Set-CommandMock 'Get-Process' { @{ ProcessName = 'Obsidian' } }
    Assert-Throws { InstallManagedPackages }
    Assert-False (Test-Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json")
}

function test_obsidian_backs_up_different_settings {
    '{"old":true}' | Set-Content "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json"
    InstallManagedPackages
    $backups = @(Get-ChildItem "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json.backup.*")
    Assert-Equals 1 $backups.Count
    if ($backups.Count) { Assert-Equals '{"old":true}' (Get-Content $backups[0].FullName) }
    InstallManagedPackages
    Assert-Equals 1 @(Get-ChildItem "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json.backup.*").Count
}

function test_obsidian_prefers_windows_override {
    $override = Join-Path $script:DotfilesDir 'config/windows/obsidian/app.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $override) | Out-Null
    '{"windows":true}' | Set-Content $override
    InstallManagedPackages
    Assert-FileExists "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json"
    if (Test-Path "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json") {
        Assert-Equals '{"windows":true}' (Get-Content "$env:DOTFILE_OBSIDIAN_VAULT/.obsidian/app.json")
    }
}
