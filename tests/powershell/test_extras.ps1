# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalFiraCodePins = @($script:FiraCodeNerdFontVersion, $script:FiraCodeNerdFontUrl, $script:FiraCodeNerdFontSha256)
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'Invoke-WebRequest', 'New-ItemProperty', 'icacls', 'fnm') { Clear-CommandMock $command }
    $script:FiraCodeNerdFontVersion, $script:FiraCodeNerdFontUrl, $script:FiraCodeNerdFontSha256 = $script:OriginalFiraCodePins
    Clear-TestEnv
}

function New-TestFontArchive($Path, $Content = 'new font') {
    $source = Join-Path $script:_TestTmp.FullName ('font-source-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $source | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'FiraCodeNerdFont-Bold.ttf'), $Content)
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $Path
}

function Use-TestFontRelease($Archive) {
    $script:FiraCodeNerdFontVersion = '9.9.9'
    $script:FiraCodeNerdFontUrl = 'https://example.test/FiraCode.zip'
    $script:FiraCodeNerdFontSha256 = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        Copy-Item -LiteralPath $script:TestFontArchive -Destination $OutFile
    }
    $script:RegisteredFonts = @{}
    Set-CommandMock 'New-ItemProperty' {
        param($Path, $Name, $Value, [switch]$Force)
        $script:RegisteredFonts[$Name] = $Value
    }
    Set-CommandMock 'icacls' { $global:LASTEXITCODE = 0 }
}

function test_grantfontreadaccess_allows_packaged_apps_to_read_fonts {
    $script:IcaclsCalls = @()
    Set-CommandMock 'icacls' {
        $script:IcaclsCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    Grant-FontReadAccess 'C:\Users\test\AppData\Local\Microsoft\Windows\Fonts'

    Assert-True ($script:IcaclsCalls -contains 'C:\Users\test\AppData\Local\Microsoft\Windows\Fonts /grant *S-1-15-2-1:(OI)(CI)(RX) /Q') 'packaged apps should receive inherited read access'
    Assert-True ($script:IcaclsCalls -contains 'C:\Users\test\AppData\Local\Microsoft\Windows\Fonts /grant *S-1-15-2-2:(OI)(CI)(RX) /Q') 'restricted packaged apps should receive inherited read access'
}

function test_installfiracodenerdfont_verifies_hash_before_extracting {
    $script:Dry = $false
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    New-TestFontArchive $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive
    $script:FiraCodeNerdFontSha256 = '0' * 64

    Assert-Throws { InstallFiraCodeNerdFont 6>&1 | Out-Null } 'font checksum mismatch should fail'
    Assert-False (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')) 'mismatched archive must not install fonts'
}

function test_installfiracodenerdfont_rejects_archive_without_fonts {
    $script:Dry = $false
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    $source = Join-Path $script:_TestTmp.FullName 'empty-font-source'
    New-Item -ItemType Directory -Force -Path $source | Out-Null
    'not a font' | Set-Content -LiteralPath (Join-Path $source 'README.txt')
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive

    Assert-Throws { InstallFiraCodeNerdFont 6>&1 | Out-Null } 'archive without font files should fail'
}

function test_installfiracodenerdfont_skips_download_when_complete_pinned_set_is_installed {
    $script:Dry = $false
    $script:FiraCodeNerdFontVersion = '9.9.9'
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $styles = 'Bold', 'Light', 'Medium', 'Regular', 'Retina', 'SemiBold'
    $families = 'FiraCodeNerdFont', 'FiraCodeNerdFontMono', 'FiraCodeNerdFontPropo'
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    foreach ($family in $families) {
        foreach ($style in $styles) {
            [IO.File]::WriteAllText((Join-Path $fontDir "$family-$style-9.9.9.ttf"), 'installed')
        }
    }
    Set-CommandMock 'Invoke-WebRequest' { throw 'download should not occur' }
    Set-CommandMock 'New-ItemProperty' {
        param($Path, $Name, $Value, [switch]$Force)
        $script:RegisteredFonts[$Name] = $Value
    }
    Set-CommandMock 'icacls' { $script:IcaclsCalls += ,($args -join ' '); $global:LASTEXITCODE = 0 }
    $script:RegisteredFonts = @{}
    $script:IcaclsCalls = @()

    InstallFiraCodeNerdFont 6>&1 | Out-Null

    Assert-Equals 18 $script:RegisteredFonts.Count 'complete font set should refresh registry entries'
    Assert-True ($script:IcaclsCalls.Count -gt 0) 'complete font set should refresh packaged-app ACL'

    Assert-Equals 'installed' ([IO.File]::ReadAllText((Join-Path $fontDir 'FiraCodeNerdFont-Regular-9.9.9.ttf'))) 'complete pinned font set should remain untouched'
}

function test_font_installer_does_not_keep_unused_wrappers_or_switches {
    Assert-False ((Get-Command InstallFiraCodeNerdFont).Parameters.ContainsKey('Update')) 'font installer should not expose unused update switch'
    Assert-False ([bool](Get-Command InstallExtras -ErrorAction SilentlyContinue)) 'font installer should not keep a single-call wrapper'
}

function test_installfiracodenerdfont_force_bypasses_fast_path {
    $script:Dry = $false
    $script:Force = $true
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    New-TestFontArchive $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive
    InstallFiraCodeNerdFont 6>&1 | Out-Null
    Assert-Equals 'new font' ([IO.File]::ReadAllText((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\FiraCodeNerdFont-Bold-9.9.9.ttf'))) 'force should refresh pinned font'
}

function test_installfiracodenerdfont_is_idempotent {
    $script:Dry = $false
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    New-TestFontArchive $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive

    InstallFiraCodeNerdFont 6>&1 | Out-Null
    $target = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\FiraCodeNerdFont-Bold-9.9.9.ttf'
    $firstWrite = (Get-Item -LiteralPath $target).LastWriteTimeUtc
    Start-Sleep -Milliseconds 20
    InstallFiraCodeNerdFont 6>&1 | Out-Null

    Assert-Equals 'new font' ([IO.File]::ReadAllText($target))
    Assert-Equals $firstWrite (Get-Item -LiteralPath $target).LastWriteTimeUtc
    Assert-Equals $target $script:RegisteredFonts['FiraCodeNerdFont-Bold (TrueType)']
}

function test_installfiracodenerdfont_upgrades_beside_locked_old_font {
    $script:Dry = $false
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    New-TestFontArchive $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    $oldFont = Join-Path $fontDir 'FiraCodeNerdFont-Bold-previous.ttf'
    [IO.File]::WriteAllText($oldFont, 'locked old font')
    $lock = [IO.File]::Open($oldFont, 'Open', 'Read', 'Read')

    try {
        InstallFiraCodeNerdFont 6>&1 | Out-Null
    } finally {
        $lock.Dispose()
    }

    Assert-Equals 'locked old font' ([IO.File]::ReadAllText($oldFont))
    Assert-Equals 'new font' ([IO.File]::ReadAllText((Join-Path $fontDir 'FiraCodeNerdFont-Bold-9.9.9.ttf')))
}

function test_installfiracodenerdfont_leaves_existing_scoop_state_untouched {
    $script:Dry = $false
    $script:TestFontArchive = Join-Path $script:_TestTmp.FullName 'FiraCode.zip'
    New-TestFontArchive $script:TestFontArchive
    Use-TestFontRelease $script:TestFontArchive
    $legacy = Join-Path $env:USERPROFILE 'scoop\apps\FiraCode-NF\current\install.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $legacy -Parent) | Out-Null
    'legacy scoop state' | Set-Content -LiteralPath $legacy

    InstallFiraCodeNerdFont 6>&1 | Out-Null

    Assert-Equals 'legacy scoop state' (Get-Content -Raw -LiteralPath $legacy).Trim()
}

function test_installfnm_uses_pi_extension_node_pin {
    $script:Dry = $false
    $nodeVersion = (Get-Content -Raw (Join-Path $script:RepoDir 'packages\pi-extensions-release.json') | ConvertFrom-Json).node.version
    $script:FnmCalls = @()
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-fnm' } }
    Set-CommandMock 'fnm' {
        $script:FnmCalls += ,($args -join ' ')
        if ($args[0] -eq 'env') { '' }
        $global:LASTEXITCODE = 0
    }

    InstallFnm 6>&1 | Out-Null

    Assert-True ($script:FnmCalls -contains "install $nodeVersion") 'fnm should install locked Node version'
    Assert-True ($script:FnmCalls -contains "use $nodeVersion") 'fnm should use locked Node version'
    Assert-True ($script:FnmCalls -contains "default $nodeVersion") 'fnm should default to locked Node version'
    Assert-False (($script:FnmCalls -join "`n") -like '*lts-latest*') 'Node version should not float'
}

function test_installfnm_fails_when_fnm_command_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'fnm') { return [pscustomobject]@{ Source = 'mock-fnm' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'fnm' { $global:LASTEXITCODE = 1 }

    Assert-Throws { InstallFnm 6>&1 | Out-Null } 'InstallFnm should fail when fnm install/use/default fails'
}
