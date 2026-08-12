param(
    # When set, skip main dispatch so the script can be
    # dot-sourced by tests to load functions without side effects.
    [switch]$NoMain,
    # Internal recursion guard used only after UpdateRepo starts this script again.
    [switch]$AfterUpdate,
    [Alias('d')][switch]$Dry,
    [Alias('f')][switch]$Force,
    [Alias('q')][switch]$Quiet,
    [Alias('h')][switch]$Help,
    [Parameter(Position = 0)][string]$Command = 'all',
    [Parameter(Position = 1)][string]$UpdateTarget = ''
)

$ErrorActionPreference = "Stop"

function Resolve-DotfilesDir($Override, $ScriptPath) {
    if ($Override) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Override)
    }
    $scriptItem = Get-Item -LiteralPath $ScriptPath
    $scriptReal = if ($scriptItem.Target) { $scriptItem.Target } else { $ScriptPath }
    return (Resolve-Path (Split-Path $scriptReal -Parent)).Path
}

# Global variables.
# Don't re-initialise $script:Dry/Quiet/Force here — at a script's top level,
# `$script:X` is the same variable as the param `$X`, so re-assigning would
# clobber values the binder just set from `-d`/`-f`/`-q` flags. Switch params
# already default to $false, which is all the reset was ever providing.
# Resolve symlink so invoking via ~\.local\bin points back to the real repo.
# Allow override via $env:DOTFILES_DIR so the install path is not hardcoded.
$script:DotfilesDir = Resolve-DotfilesDir $env:DOTFILES_DIR $PSCommandPath
# Reviewed immutable installer pin; Scoop publishes no checksum or signed release.
$script:ScoopInstallerCommit = 'b0ee913725139b816f9178163af0aecdba07a7ed'
$script:ScoopInstallerSha256 = '48f6ea398b3a3fa26fae0093d37bd85b13e7eaa5d1d4a3e208408768408e35ae'
$script:ScoopCoreCommit = 'b588a06e41d920d2123ec70aee682bae14935939'
$script:ScoopCoreSha256 = '630206995f30866a0b25b00c14c74be9ef9b79c4911f72f6efd2625cfe19a645'
$script:ScoopMainCommit = 'f06f06f4ffbe5028735b98173fc5ef0427da6da4'
$script:ScoopMainSha256 = '04ab17ccf5aeadfeb3951b35a6c037677ceda5ba411aa510546c5c996e614c76'

# Logging helpers
function Info($msg) { if (-not $script:Quiet) { Write-Host "  [ .. ] $msg" } }
function Success($msg) { if (-not $script:Quiet) { Write-Host "  [ OK ] $msg" -ForegroundColor Green } }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }
function FailSoft($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# File helpers
function PromptAction($destination, $sourceName) {
    Write-Host "  [ ?? ] File already exists: $destination ($sourceName)"
    Write-Host "         [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all"
    $key = [System.Console]::ReadKey($true).KeyChar
    return $key
}

function Get-LinkConflict($source, $destination) {
    $current = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if ($null -eq $current) { return $null }

    [pscustomobject]@{
        Item = $current
        AlreadyLinked = ($current.Target -eq $source)
    }
}

function Invoke-ElevatedSymlink($source, $destination) {
    $escapedSource = $source.Replace("'", "''")
    $escapedDestination = $destination.Replace("'", "''")
    $command = "New-Item -ItemType SymbolicLink -Path '$escapedDestination' -Target '$escapedSource' | Out-Null"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded) -Verb RunAs -Wait -PassThru
    if ($elevated.ExitCode -ne 0) { throw "Elevated symlink creation failed: $destination" }
}

function Test-SymlinkPrivilegeError($exception) {
    while ($exception) {
        if ($exception -is [System.UnauthorizedAccessException] -or
            $exception.NativeErrorCode -eq 1314 -or
            $exception.HResult -eq -2147023582 -or
            $exception.Message -match 'required privilege') {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function New-Symlink($source, $destination) {
    $parent = Split-Path $destination -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    try {
        New-Item -ItemType SymbolicLink -Path $destination -Target $source | Out-Null
    } catch {
        if ($NoMain -or -not (Test-SymlinkPrivilegeError $_.Exception)) { throw }
        Invoke-ElevatedSymlink $source $destination
    }
}

function LinkPath($source, $destination, [bool]$isDirectory = $false) {
    Info "Linking $(if ($isDirectory) { 'directory ' })$source to $destination"
    if ($script:Dry) { return }

    $skip = $false
    $overwrite = $false
    $backup = $false
    $conflict = Get-LinkConflict $source $destination
    if ($conflict) {
        if ($conflict.AlreadyLinked) {
            Success "Skipped $destination (already linked)"
            return
        }

        if ($isDirectory) {
            $overwrite = $script:Force
            $backup = -not $script:Force
        } elseif (-not $script:OverwriteAll -and -not $script:BackupAll -and -not $script:SkipAll) {
            switch (PromptAction $destination (Split-Path $source -Leaf)) {
                'o' { $overwrite = $true }
                'O' { $script:OverwriteAll = $true }
                'b' { $backup = $true }
                'B' { $script:BackupAll = $true }
                's' { $skip = $true }
                'S' { $script:SkipAll = $true }
                default { $skip = $true }
            }
        }

        if ($script:OverwriteAll -or $overwrite) {
            $recurse = $conflict.Item.PSIsContainer -and -not $conflict.Item.LinkType
            Remove-Item $destination -Force -Recurse:$recurse
            Success "Removed $destination"
        }
        if ($script:BackupAll -or $backup) {
            $backupPath = "$destination.bak"
            $oldBackup = Get-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            if ($oldBackup) {
                $recurse = $oldBackup.PSIsContainer -and -not $oldBackup.LinkType
                Remove-Item -LiteralPath $backupPath -Force -Recurse:$recurse -ErrorAction Stop
            }
            Rename-Item -LiteralPath $destination -NewName (Split-Path $backupPath -Leaf) -ErrorAction Stop
            Success "Moved $destination to $backupPath"
        }
        if ($script:SkipAll -or $skip) {
            Success "Skipped $source"
            return
        }
    }

    New-Symlink $source $destination
    Success "Linked $source to $destination"
}

function Invoke-Winget($FailureMessage, [string[]]$Arguments) {
    winget @Arguments --disable-interactivity --accept-package-agreements --accept-source-agreements
    # WinGet reports an already-current package as APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE.
    if ($Arguments[0] -eq 'upgrade' -and $LASTEXITCODE -eq -1978335189) { return }
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function UpdateRepo {
    Info "Updating dotfiles repo..."
    if (-not $script:Dry) {
        git -C $script:DotfilesDir pull --rebase --autostash
        if ($LASTEXITCODE -ne 0) { Fail "Failed to pull dotfiles repo" }
    }
    Success "Finished updating repo"
}

function WingetHas($id) {
    $null = winget list --id $id --exact --accept-source-agreements 2>$null | Out-String
    return ($LASTEXITCODE -eq 0)
}

function Get-WingetPackages {
    @(
        "Microsoft.PowerShell", "Git.Git", "GnuPG.Gpg4win", "Microsoft.WindowsTerminal",
        "Neovim.Neovim", "Starship.Starship", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd", "junegunn.fzf",
        "tree-sitter.tree-sitter-cli", "LLVM.LLVM",
        "Schniz.fnm", "jj-vcs.jj", "ajeetdsouza.zoxide",
        "Python.Python.3.14", "GitHub.cli", "Notepad++.Notepad++", "koalaman.shellcheck"
    )
}

function Get-ScoopPackages {
    @("FiraCode-NF", "jq")
}

function Get-RequiredCommands {
    @(
        "git", "gpg", "nvim", "starship", "fzf", "fd", "rg", "lazygit",
        "fnm", "node", "jj", "zoxide", "jq", "codex", "pi",
        "codebase-memory-mcp", "fff-mcp", "fff-mcp-agent", "py", "gh", "vtsls",
        "bash-language-server", "shellcheck", "tree-sitter", "clang"
    )
}

function Invoke-NativeChecked($FailureMessage, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function InstallPackages {
    Info "Installing packages..."
    if ($script:Dry) { return }

    $wingetPkgs = @(Get-WingetPackages)
    Info "Checking winget packages ($($wingetPkgs.Count) total)..."
    $missing = @()
    for ($i = 0; $i -lt $wingetPkgs.Count; $i++) {
        $pkg = $wingetPkgs[$i]
        Info "  [$($i + 1)/$($wingetPkgs.Count)] Checking $pkg..."
        if (-not (WingetHas $pkg)) { $missing += $pkg }
    }
    if ($missing.Count -gt 0) {
        Info "Installing $($missing.Count) missing winget package(s): $($missing -join ', ')"
        foreach ($pkg in $missing) {
            Invoke-Winget "winget install $pkg failed" @('install', '--id', $pkg, '--exact')
        }
    } else {
        Success "All winget packages already installed"
    }

    Info "Upgrading managed winget packages..."
    foreach ($pkg in $wingetPkgs) {
        Invoke-Winget "winget upgrade $pkg failed" @('upgrade', '--id', $pkg, '--exact')
    }

    Success "Finished installing packages"
}

function Get-StreamSha256($Stream) {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($Stream)
    } finally {
        $sha256.Dispose()
        $Stream.Position = 0
    }
    return ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
}

function Get-FileSha256($Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return Get-StreamSha256 $stream } finally { $stream.Dispose() }
}

function Set-ScoopBootstrapArchives($Source, $CoreUri, $MainUri) {
    $CoreUri = $CoreUri.Replace("'", "''")
    $MainUri = $MainUri.Replace("'", "''")
    $replacements = [ordered]@{
        "if (Test-CommandAvailable('git')) {" = 'if ($false) {'
        "`$SCOOP_PACKAGE_REPO = 'https://github.com/ScoopInstaller/Scoop/archive/master.zip'" = "`$SCOOP_PACKAGE_REPO = '$CoreUri'"
        "`$SCOOP_MAIN_BUCKET_REPO = 'https://github.com/ScoopInstaller/Main/archive/master.zip'" = "`$SCOOP_MAIN_BUCKET_REPO = '$MainUri'"
    }
    foreach ($entry in $replacements.GetEnumerator()) {
        if ([regex]::Matches($Source, [regex]::Escape($entry.Key)).Count -ne 1) {
            throw "Unexpected Scoop installer source"
        }
        $Source = $Source.Replace($entry.Key, $entry.Value)
    }
    return $Source
}

function InstallScoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return }

    $uri = "https://raw.githubusercontent.com/ScoopInstaller/Install/$script:ScoopInstallerCommit/install.ps1"
    $installer = Join-Path ([IO.Path]::GetTempPath()) "scoop-install-$([Guid]::NewGuid().ToString('N')).ps1"
    try {
        Invoke-WebRequest -Uri $uri -OutFile $installer -UseBasicParsing
        $bytes = [IO.File]::ReadAllBytes($installer)
        $stream = [IO.MemoryStream]::new($bytes, $false)
        try {
            $actual = Get-StreamSha256 $stream
        } finally {
            $stream.Dispose()
        }
        if ($actual -ne $script:ScoopInstallerSha256) {
            throw "Scoop installer checksum mismatch"
        }
        $source = [Text.Encoding]::UTF8.GetString($bytes)
    } finally {
        if (Test-Path -LiteralPath $installer) {
            Remove-Item -LiteralPath $installer -Force -ErrorAction Stop
        }
    }

    $temp = [IO.Path]::GetTempPath()
    $coreArchive = Join-Path $temp "scoop-core-$([Guid]::NewGuid().ToString('N')).zip"
    $mainArchive = Join-Path $temp "scoop-main-$([Guid]::NewGuid().ToString('N')).zip"
    $coreLock = $null
    $mainLock = $null
    try {
        $coreUri = "https://github.com/ScoopInstaller/Scoop/archive/$script:ScoopCoreCommit.zip"
        $mainUri = "https://github.com/ScoopInstaller/Main/archive/$script:ScoopMainCommit.zip"
        Invoke-WebRequest -Uri $coreUri -OutFile $coreArchive -UseBasicParsing
        Invoke-WebRequest -Uri $mainUri -OutFile $mainArchive -UseBasicParsing
        $coreLock = [IO.File]::Open($coreArchive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $mainLock = [IO.File]::Open($mainArchive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Get-StreamSha256 $coreLock) -ne $script:ScoopCoreSha256) {
            throw "Scoop core archive checksum mismatch"
        }
        if ((Get-StreamSha256 $mainLock) -ne $script:ScoopMainSha256) {
            throw "Scoop Main archive checksum mismatch"
        }
        $coreLocalUri = [Uri]::new((Resolve-Path -LiteralPath $coreArchive).Path).AbsoluteUri
        $mainLocalUri = [Uri]::new((Resolve-Path -LiteralPath $mainArchive).Path).AbsoluteUri
        $source = Set-ScoopBootstrapArchives $source $coreLocalUri $mainLocalUri
        $bootstrap = [ScriptBlock]::Create($source)

        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        do { & $bootstrap -RunAsAdmin } while ($false)
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            throw "scoop command not found after installation"
        }
    } finally {
        if ($coreLock) { $coreLock.Dispose() }
        if ($mainLock) { $mainLock.Dispose() }
        $cleanupError = $null
        foreach ($path in $coreArchive, $mainArchive) {
            try {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                }
            } catch {
                if (-not $cleanupError) { $cleanupError = $_.Exception }
            }
        }
        if ($cleanupError) { throw $cleanupError }
    }
}

function InstallScoopPackages {
    Info "Installing Scoop packages..."
    if ($script:Dry) { return }

    InstallScoop
    $buckets = scoop bucket list
    if ($LASTEXITCODE -ne 0) { throw "scoop bucket list failed" }
    $fontBucket = @($buckets | Where-Object { $_.Name -eq "nerd-fonts" }) | Select-Object -First 1
    if ($fontBucket -and $fontBucket.Source -notmatch '^https://github\.com/matthewjberger/scoop-nerd-fonts(?:\.git)?/?$') {
        throw "Unexpected nerd-fonts bucket source: $($fontBucket.Source)"
    }
    if (-not $fontBucket) {
        foreach ($package in "FiraCode", "FiraCode-NF") {
            $prefix = @(scoop prefix $package 2>$null 6>$null)
            if ($LASTEXITCODE -ne 0 -or $prefix.Count -eq 0) { continue }
            $installInfoPath = Join-Path ($prefix | Select-Object -Last 1) "install.json"
            $installInfo = if (Test-Path -LiteralPath $installInfoPath) {
                Get-Content -Raw -LiteralPath $installInfoPath | ConvertFrom-Json
            }
            if ($package -eq "FiraCode" -or $installInfo.bucket -eq "nerd-fonts") {
                Invoke-NativeChecked "scoop uninstall $package failed" { scoop uninstall $package }
            }
        }
    }

    $installed = @(scoop list)
    if ($LASTEXITCODE -ne 0) { throw "scoop list failed" }
    $fontManifest = Join-Path $script:DotfilesDir "config\windows\scoop\FiraCode-NF.json"
    $installedFont = @($installed | Where-Object { $_.Name -eq "FiraCode-NF" }) | Select-Object -First 1
    if ($installedFont) {
        $fontIsCurrent = $false
        if ($installedFont.Source -eq $fontManifest) {
            $fontPrefix = @(scoop prefix FiraCode-NF)
            if ($LASTEXITCODE -ne 0) { throw "scoop prefix FiraCode-NF failed" }
            $installedManifest = Join-Path ($fontPrefix | Select-Object -Last 1) "manifest.json"
            if (Test-Path -LiteralPath $installedManifest) {
                $trackedJson = Get-Content -Raw -LiteralPath $fontManifest | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
                $installedJson = Get-Content -Raw -LiteralPath $installedManifest | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
                $fontIsCurrent = $trackedJson -ceq $installedJson
            }
        }
        if (-not $fontIsCurrent) {
            Invoke-NativeChecked "scoop uninstall FiraCode-NF failed" { scoop uninstall FiraCode-NF }
            $installed = @($installed | Where-Object { $_.Name -ne "FiraCode-NF" })
        }
    }
    if ($installed.Name -contains "FiraCode") {
        Invoke-NativeChecked "scoop uninstall FiraCode failed" { scoop uninstall FiraCode }
        $installed = @($installed | Where-Object { $_.Name -ne "FiraCode" })
    }
    if ($installed.Name -contains "ast-grep") {
        Invoke-NativeChecked "scoop uninstall ast-grep failed" { scoop uninstall ast-grep }
        $installed = @($installed | Where-Object { $_.Name -ne "ast-grep" })
    }
    if ($fontBucket) {
        Invoke-NativeChecked "scoop bucket rm nerd-fonts failed" { scoop bucket rm nerd-fonts }
    }
    foreach ($package in Get-ScoopPackages) {
        if ($installed.Name -notcontains $package) {
            $target = if ($package -eq "FiraCode-NF") { $fontManifest } else { $package }
            Invoke-NativeChecked "scoop install $package failed" { scoop install $target }
        }
    }

    Success "Finished installing Scoop packages"
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-PiExtensionsPins {
    $path = Join-Path $script:DotfilesDir "packages\pi-extensions-release.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pi extension release pins not found: $path" }
    $pins = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ([string]$pins.releaseId -notmatch '^[0-9a-f]{64}$') { throw "Invalid Pi extension release ID" }
    if ([string]$pins.node.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Pi extension Node version" }
    if ([string]$pins.node.abi -notmatch '^\d+$') { throw "Invalid Pi extension Node ABI" }
    if ([string]$pins.betterSqlite3.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid better-sqlite3 version" }
    foreach ($key in 'windows-x64', 'windows-arm64') {
        $asset = $pins.betterSqlite3.assets.$key
        if (-not $asset -or [string]$asset.file -notmatch '^better-sqlite3-[0-9A-Za-z.-]+\.tar\.gz$' -or [string]$asset.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Invalid better-sqlite3 asset pins for $key"
        }
    }
    return $pins
}

function InstallFnm {
    Info "Installing Node.js LTS via fnm..."
    if ($script:Dry) { return }

    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        Refresh-ProcessPath
    }
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        FailSoft "fnm not found on PATH. Skipping Node.js LTS install — open a new shell and re-run 'dotfile.ps1'."
        return
    }

    $nodeVersion = [string](Get-PiExtensionsPins).node.version
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    Invoke-NativeChecked "fnm install $nodeVersion failed" { fnm install $nodeVersion }
    Invoke-NativeChecked "fnm use $nodeVersion failed" { fnm use $nodeVersion }
    Invoke-NativeChecked "fnm default $nodeVersion failed" { fnm default $nodeVersion }

    Success "Finished installing pinned Node.js"
}

function InstallExtras {
    param([switch]$Update)
    InstallScoopPackages
    InstallFnm
}

function InstallManagedPackages {
    InstallPackages
    InstallExtras
    InstallAi
}

function Get-CodexWindowsTarget($Architecture) {
    switch ([string]$Architecture) {
        "X64" { return "x86_64-pc-windows-msvc" }
        "Arm64" { return "aarch64-pc-windows-msvc" }
        default { throw "Unsupported Codex Windows architecture: $Architecture" }
    }
}

function Get-CodexPathValue($PathValue, $BinDir, $ManagedRoot) {
    $managedRootNormalized = $ManagedRoot.TrimEnd("\", "/")
    $legacyBin = Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin"
    $entries = @($PathValue -split ";" | Where-Object {
        if (-not $_) { return $false }
        $entry = $_.TrimEnd("\", "/")
        return $entry -ine $BinDir.TrimEnd("\", "/") -and
            $entry -ine $legacyBin.TrimEnd("\", "/") -and
            -not $entry.StartsWith("$managedRootNormalized\", [StringComparison]::OrdinalIgnoreCase) -and
            -not $entry.StartsWith("$managedRootNormalized/", [StringComparison]::OrdinalIgnoreCase)
    })
    return (@($BinDir) + $entries) -join ";"
}

function Test-CodexRelease($ReleaseDir, $ExpectedVersion) {
    foreach ($relativePath in @(
        "codex-package.json",
        "bin\codex.exe",
        "bin\codex-code-mode-host.exe",
        "codex-path\rg.exe",
        "codex-resources\codex-command-runner.exe",
        "codex-resources\codex-windows-sandbox-setup.exe"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $relativePath) -PathType Leaf)) { return $false }
    }

    try {
        $versionOutput = & (Join-Path $ReleaseDir "bin\codex.exe") --version 2>$null
    } catch {
        return $false
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    $match = [regex]::Match(($versionOutput -join " "), "([0-9][0-9A-Za-z.+-]*)$")
    return $match.Success -and $match.Groups[1].Value -ceq $ExpectedVersion
}

function Set-CodexActivePath($BinDir, $ManagedRoot) {
    $oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    try {
        [Environment]::SetEnvironmentVariable("Path", (Get-CodexPathValue $oldUserPath $BinDir $ManagedRoot), "User")
    } catch {
        [Environment]::SetEnvironmentVariable("Path", $oldUserPath, "User")
        throw
    }
}

function InstallCodex {
    param([switch]$Update)
    Info "Installing Codex CLI..."
    if ($script:Dry) { return }
    if (-not [Environment]::Is64BitOperatingSystem) { throw "Codex requires 64-bit Windows" }

    $pinsPath = Join-Path $script:DotfilesDir "packages\codex-release.json"
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing Codex pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid pinned Codex version: $version" }

    $target = Get-CodexWindowsTarget ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
    $architecture = if ($target.StartsWith("x86_64")) { "x86_64" } else { "aarch64" }
    $expectedHash = [string]$pins.windows.$architecture
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') { throw "Invalid pinned Codex checksum for $architecture" }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE ".codex" } else { $env:CODEX_HOME }
    $standaloneRoot = Join-Path $codexHome "packages\standalone"
    $releasesDir = Join-Path $standaloneRoot "releases"
    $releaseDir = Join-Path $releasesDir "$version-$target-$($expectedHash.Substring(0, 12))"
    $binDir = Join-Path $releaseDir "bin"
    New-Item -ItemType Directory -Force -Path $standaloneRoot | Out-Null
    $installLock = [IO.File]::Open((Join-Path $standaloneRoot "install.lock"), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    try {
        if ((Test-Path -LiteralPath $releaseDir) -and -not (Test-CodexRelease $releaseDir $version)) {
            throw "Pinned Codex release is incomplete: $releaseDir"
        }
        if (-not (Test-Path -LiteralPath $releaseDir)) {
            if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { throw "tar command not found for Codex package extraction" }
            New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) "codex-install-$([Guid]::NewGuid().ToString('N'))"
            $stagingDir = Join-Path $releasesDir ".staging.$([Guid]::NewGuid().ToString('N'))"
            $archive = Join-Path $tempDir "codex-package-$target.tar.gz"
            $archiveLock = $null
            try {
                New-Item -ItemType Directory -Force -Path $tempDir, $stagingDir | Out-Null
                $uri = "https://github.com/openai/codex/releases/download/rust-v$version/codex-package-$target.tar.gz"
                Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
                $archiveLock = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if ((Get-StreamSha256 $archiveLock) -ne $expectedHash) { throw "Codex package checksum mismatch" }
                Invoke-NativeChecked "Codex package extraction failed" { tar -xzf $archive -C $stagingDir }
                if (-not (Test-CodexRelease $stagingDir $version)) { throw "Codex package is incomplete or has wrong version" }
                $archiveLock.Dispose()
                $archiveLock = $null
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction Stop
                Move-Item -LiteralPath $stagingDir -Destination $releaseDir
            } catch {
                $operationError = $_
                if ($archiveLock) { $archiveLock.Dispose(); $archiveLock = $null }
                $cleanupError = $null
                foreach ($path in $tempDir, $stagingDir) {
                    try {
                        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
                    } catch {
                        if (-not $cleanupError) { $cleanupError = $_.Exception }
                    }
                }
                if ($cleanupError) { throw "Codex cleanup failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
                throw $operationError
            } finally {
                if ($archiveLock) { $archiveLock.Dispose() }
            }
        }

        if (-not (Test-CodexRelease $releaseDir $version)) { throw "Installed Codex release verification failed" }
        Set-CodexActivePath $binDir $releasesDir
    } finally {
        $installLock.Dispose()
    }

    Success "Finished installing Codex CLI"
}

function SyncCodexConfig {
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $source -Destination $target
    } else {
        $applySeed = ''
        Invoke-NativeChecked 'Codex config seed comparison failed' {
            py -3.14 (Join-Path $script:DotfilesDir 'scripts\seed_merge\codex.py') $target $source $applySeed
        }
    }
    (Get-Item -LiteralPath $target).IsReadOnly = $false
}

function Get-PinnedPiVersion {
    $lockPath = Join-Path $script:DotfilesDir 'packages\pi-agent-npm-shrinkwrap.json'
    if (-not (Test-Path -LiteralPath $lockPath)) { throw "Missing Pi package lock: $lockPath" }
    $lock = Get-Content -Raw -LiteralPath $lockPath
    if ($lock -notmatch '^\s*\{\s*"name"\s*:\s*"@earendil-works/pi-coding-agent"\s*,\s*"version"\s*:\s*"([^"]+)"') {
        throw "Failed to parse pinned Pi version: $lockPath"
    }
    $version = $Matches[1]
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid pinned Pi version: $version" }
    return $version
}

function Get-PiExtensionsWindowsArch($Architecture = $env:PROCESSOR_ARCHITECTURE) {
    switch ([string]$Architecture) {
        'AMD64' { return 'windows-x64' }
        'X64' { return 'windows-x64' }
        'ARM64' { return 'windows-arm64' }
        'Arm64' { return 'windows-arm64' }
        default { throw "Unsupported Pi extension Windows architecture: $Architecture" }
    }
}

function Test-PiExtensionsRelease($ReleaseDir, $Pins) {
    if (-not (Test-Path -LiteralPath $ReleaseDir -PathType Container)) { return $false }
    $releaseItem = Get-Item -LiteralPath $ReleaseDir -Force
    if (($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    $lockPath = Join-Path $ReleaseDir 'package-lock.json'
    $packagePath = Join-Path $ReleaseDir 'package.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf) -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return $false }
    if ((Get-FileSha256 $lockPath) -ne [string]$Pins.releaseId) { return $false }
    try { $manifest = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json } catch { return $false }
    $nodeModules = Join-Path $ReleaseDir 'node_modules'
    foreach ($dependency in $manifest.dependencies.PSObject.Properties) {
        $installedManifest = Join-Path (Join-Path $nodeModules $dependency.Name) 'package.json'
        if (-not (Test-Path -LiteralPath $installedManifest -PathType Leaf)) { return $false }
        try { $installed = Get-Content -Raw -LiteralPath $installedManifest | ConvertFrom-Json } catch { return $false }
        if ([string]$installed.version -ne [string]$dependency.Value) { return $false }
    }
    $betterManifest = Join-Path $nodeModules 'better-sqlite3\package.json'
    $betterBinary = Join-Path $nodeModules 'better-sqlite3\build\Release\better_sqlite3.node'
    if (-not (Test-Path -LiteralPath $betterManifest -PathType Leaf) -or -not (Test-Path -LiteralPath $betterBinary -PathType Leaf)) { return $false }
    try { $better = Get-Content -Raw -LiteralPath $betterManifest | ConvertFrom-Json } catch { return $false }
    return [string]$better.version -eq [string]$Pins.betterSqlite3.version
}

function InstallPiExtensions {
    Info "Installing integrity-locked Pi extensions..."
    if ($script:Dry) { return }

    $pins = Get-PiExtensionsPins
    $source = Join-Path $script:DotfilesDir 'config\shared\ai\pi\extensions'
    $sourceLock = Join-Path $source 'package-lock.json'
    if (-not (Test-Path -LiteralPath $sourceLock -PathType Leaf) -or (Get-FileSha256 $sourceLock) -ne [string]$pins.releaseId) {
        throw "Pi extension package lock does not match release pins"
    }
    foreach ($command in 'node', 'npm', 'tar') {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command command not found for Pi extensions" }
    }
    $nodeVersion = (& node --version 2>$null | Select-Object -Last 1).TrimStart('v')
    if ($LASTEXITCODE -ne 0 -or $nodeVersion -ne [string]$pins.node.version) { throw "Pi extensions require Node $($pins.node.version)" }
    $nodeAbi = (& node -p 'process.versions.modules' 2>$null | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or $nodeAbi -ne [string]$pins.node.abi) { throw "Pi extensions require Node ABI $($pins.node.abi)" }

    $asset = $pins.betterSqlite3.assets.(Get-PiExtensionsWindowsArch)
    $root = Join-Path $env:USERPROFILE '.pi\agent\locked-extensions'
    $releases = Join-Path $root 'releases'
    $release = Join-Path $releases ([string]$pins.releaseId)
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $installLock = [IO.File]::Open((Join-Path $root 'install.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if (Test-Path -LiteralPath $release) {
            if (-not (Test-PiExtensionsRelease $release $pins)) { throw "Pinned Pi extension release is incomplete: $release" }
            return
        }

        New-Item -ItemType Directory -Force -Path $releases | Out-Null
        $staging = Join-Path $releases ".staging.$([Guid]::NewGuid().ToString('N'))"
        $archive = Join-Path $staging ([string]$asset.file)
        try {
            New-Item -ItemType Directory -Force -Path $staging | Out-Null
            Copy-Item -LiteralPath (Join-Path $source 'package.json'), $sourceLock -Destination $staging
            $stagedLock = Join-Path $staging 'package-lock.json'
            $lockStream = [IO.File]::Open($stagedLock, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ((Get-StreamSha256 $lockStream) -ne [string]$pins.releaseId) { throw "Staged Pi extension package lock mismatch" }
                Invoke-NativeChecked "Pi extension npm ci failed" { npm ci --prefix $staging --omit=dev --ignore-scripts --legacy-peer-deps }
            } finally { $lockStream.Dispose() }

            $uri = "https://github.com/WiseLibs/better-sqlite3/releases/download/v$($pins.betterSqlite3.version)/$($asset.file)"
            Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
            $archiveStream = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ((Get-StreamSha256 $archiveStream) -ne [string]$asset.sha256) { throw "better-sqlite3 package checksum mismatch" }
                $betterDir = Join-Path $staging 'node_modules\better-sqlite3'
                Invoke-NativeChecked "better-sqlite3 package extraction failed" { tar -xzf $archive -C $betterDir }
            } finally { $archiveStream.Dispose() }
            Remove-Item -LiteralPath $archive -Force -ErrorAction Stop
            if (-not (Test-PiExtensionsRelease $staging $pins)) { throw "Installed Pi extension release verification failed" }
            Move-Item -LiteralPath $staging -Destination $release
        } finally {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
        }
    } finally { $installLock.Dispose() }

    Success "Finished installing integrity-locked Pi extensions"
}

function RepairPiCompactionSteering {
    param([string]$AgentSessionPath)

    if (-not $AgentSessionPath) {
        $piCommand = Get-Command pi -ErrorAction SilentlyContinue
        if (-not $piCommand) { throw "pi command not found for compaction repair" }
        $AgentSessionPath = Join-Path (Split-Path -Parent $piCommand.Source) 'node_modules\@earendil-works\pi-coding-agent\dist\core\agent-session.js'
    }
    if (-not (Test-Path -LiteralPath $AgentSessionPath -PathType Leaf)) {
        throw "Pi agent session runtime not found: $AgentSessionPath"
    }
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "py is required to repair Pi compaction steering"
    }

    $patch = Join-Path $script:DotfilesDir 'scripts\patch_pi_compaction.py'
    Invoke-NativeChecked "Pi compaction steering repair failed" {
        py -3.14 $patch $AgentSessionPath
    }
}

function InstallPi {
    param([switch]$Update)
    Info "Installing Pi coding agent..."
    if ($script:Dry) { return }

    $pinnedVersion = Get-PinnedPiVersion
    $piCommand = Get-Command pi -ErrorAction SilentlyContinue
    $install = -not $piCommand
    if ($Update -and $piCommand) {
        $currentVersion = & pi --version 2>$null | Select-Object -Last 1
        $install = -not $currentVersion -or $currentVersion.Trim() -ne $pinnedVersion
    }

    if ($install) {
        Invoke-NativeChecked "Pi install failed" {
            npm install --global "@earendil-works/pi-coding-agent@$pinnedVersion"
        }
    } else {
        Info "Already installed Pi coding agent"
    }
    Refresh-ProcessPath
    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        throw "pi command not found after installation"
    }
    RepairPiCompactionSteering
    Success "Finished installing Pi coding agent"
}

function InstallPiLanguageServers {
    param([switch]$Update)
    Info "Installing Pi language servers..."
    if ($script:Dry) { return }

    $servers = [ordered]@{
        'vtsls' = '0.3.0'
        'bash-language-server' = '5.6.0'
    }
    $needsInstall = [bool]$Update
    foreach ($name in $servers.Keys) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            $needsInstall = $true
            continue
        }
        $version = & $name --version 2>$null | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0 -or -not $version -or $version.Trim() -ne $servers[$name]) {
            $needsInstall = $true
        }
    }

    if ($needsInstall) {
        Invoke-NativeChecked "Pi language-server install failed" {
            npm install --global @vtsls/language-server@0.3.0 bash-language-server@5.6.0
        }
    }
    if (-not (Get-Command shellcheck -ErrorAction SilentlyContinue)) {
        Invoke-Winget "ShellCheck install failed" @('install', '--id', 'koalaman.shellcheck', '--exact')
    }
    Refresh-ProcessPath

    foreach ($name in $servers.Keys) {
        $version = & $name --version 2>$null | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0 -or -not $version -or $version.Trim() -ne $servers[$name]) {
            throw "$name $($servers[$name]) not found after installation"
        }
    }
    if (-not (Get-Command shellcheck -ErrorAction SilentlyContinue)) {
        throw "shellcheck not found after installation"
    }
    Success "Finished installing Pi language servers"
}

function SyncPiConfigs {
    Info "Syncing Pi configuration..."
    if ($script:Dry) { return }

    $seedDir = Join-Path $script:DotfilesDir "config\shared\ai\pi"
    $targetDir = Join-Path $env:USERPROFILE ".pi\agent"
    $baseDir = Join-Path $env:LOCALAPPDATA "dotfiles\pi"
    New-Item -ItemType Directory -Force -Path $targetDir, $baseDir | Out-Null

    foreach ($name in @("settings.json", "mcp.json", "subagent-config.json")) {
        $source = if ($name -eq "mcp.json") {
            Join-Path $script:DotfilesDir "config\windows\ai\pi\mcp.json"
        } else {
            Join-Path $seedDir $name
        }
        $relative = if ($name -eq "subagent-config.json") { "extensions\subagent\config.json" } else { $name }
        $target = Join-Path $targetDir $relative
        $base = Join-Path $baseDir $name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        if ($name -eq "subagent-config.json") {
            foreach ($destination in $target, $base) {
                $temp = "$destination.tmp.$([Guid]::NewGuid().ToString('N'))"
                Copy-Item -LiteralPath $source -Destination $temp
                Move-Item -LiteralPath $temp -Destination $destination -Force
            }
            continue
        }
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $source -Destination $target
            Copy-Item -LiteralPath $source -Destination $base
            continue
        }

        if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
            throw "py is required to sync Pi configuration"
        }

        $mergeScript = Join-Path $script:DotfilesDir "scripts\seed_merge\pi.py"
        $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { "" } else { $source }
        Invoke-NativeChecked "Pi $name seed comparison failed" {
            py -3.14 $mergeScript $target $source $applySeed $base
        }
    }

    $lspSource = Join-Path $script:DotfilesDir 'config\windows\ai\pi\pi-lsp.json'
    Copy-Item -LiteralPath $lspSource -Destination (Join-Path $targetDir 'pi-lsp.json') -Force

    $extensionDir = Join-Path $targetDir "extensions"
    New-Item -ItemType Directory -Force -Path $extensionDir | Out-Null
    foreach ($name in @("caveman-default.js", "ponytail-default.js", "codex-status.js", "windows-exit.js")) {
        Copy-Item -LiteralPath (Join-Path $seedDir $name) -Destination (Join-Path $extensionDir $name) -Force
    }
    Success "Finished syncing Pi configuration"
}

function InstallFffMcp {
    param([switch]$Update)
    Info "Installing FFF MCP server..."
    if ($script:Dry) { return }

    $pinsPath = Join-Path $script:DotfilesDir 'packages\fff-release.json'
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing FFF pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    $asset = $pins.mcp.'windows-x64'
    $assetFile = [string]$asset.file
    $expectedHash = [string]$asset.sha256
    if ($version -notmatch '^\d+\.\d+\.\d+$' -or $assetFile -ne 'fff-mcp-x86_64-pc-windows-msvc.exe' -or $expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw 'Invalid pinned FFF MCP release'
    }

    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    $destination = Join-Path $binDir 'fff-mcp.exe'
    if ($Update -or -not (Test-Path -LiteralPath $destination)) {
        $url = "https://github.com/dmtrKovalenko/fff/releases/download/v$version/$assetFile"
        $download = "$destination.download"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        try {
            Invoke-WebRequest -Uri $url -OutFile $download
            if ((Get-FileHash -Algorithm SHA256 $download).Hash -ne $expectedHash) {
                throw 'FFF MCP download hash mismatch'
            }
            Move-Item -LiteralPath $download -Destination $destination -Force
        } finally {
            Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
        }
    } else {
        Info "Already installed FFF MCP server"
    }
    $launcher = Join-Path $binDir 'fff-mcp-agent.cmd'
    @'
@echo off
"%~dp0fff-mcp.exe" --frecency-db "%LOCALAPPDATA%\fff\frecency" %*
'@ | Set-Content -LiteralPath $launcher -Encoding ascii
    AddToUserPath $binDir

    Success "Finished installing FFF MCP server"
}

function Get-CodebaseMemoryWindowsArch($Architecture) {
    switch ([string]$Architecture) {
        "X64" { return "amd64" }
        "Arm64" { return "arm64" }
        default { throw "Unsupported codebase-memory Windows architecture: $Architecture" }
    }
}

function Get-CodebaseMemoryPathValue($PathValue, $ReleaseDir, $ReleasesRoot, $LegacyRoot) {
    $releasesNormalized = $ReleasesRoot.TrimEnd("\", "/")
    $releaseNormalized = $ReleaseDir.TrimEnd("\", "/")
    $legacyNormalized = $LegacyRoot.TrimEnd("\", "/")
    $entries = @($PathValue -split ";" | Where-Object {
        if (-not $_) { return $false }
        $entry = $_.TrimEnd("\", "/")
        return $entry -ine $releaseNormalized -and
            $entry -ine $legacyNormalized -and
            -not $entry.StartsWith("$releasesNormalized\", [StringComparison]::OrdinalIgnoreCase) -and
            -not $entry.StartsWith("$releasesNormalized/", [StringComparison]::OrdinalIgnoreCase)
    })
    return (@($ReleaseDir) + $entries) -join ";"
}

function Set-CodebaseMemoryActivePath($ReleaseDir, $ReleasesRoot, $LegacyRoot) {
    $oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    try {
        $newUserPath = Get-CodebaseMemoryPathValue $oldUserPath $ReleaseDir $ReleasesRoot $LegacyRoot
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    } catch {
        [Environment]::SetEnvironmentVariable("Path", $oldUserPath, "User")
        throw
    }
}

function Test-CodebaseMemoryArchive($Archive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $expected = @("codebase-memory-mcp.exe", "LICENSE", "install.ps1", "THIRD_PARTY_NOTICES.md")
        if ($names.Count -ne $expected.Count) { return $false }
        foreach ($name in $expected) {
            if ($names -cnotcontains $name) { return $false }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Get-CodebaseMemoryVersionFromOutput($Output) {
    $match = [regex]::Match(($Output -join " "), "(?:^|\s)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$")
    if ($match.Success) { return $match.Groups[1].Value }
    return ""
}

function Test-CodebaseMemoryRelease($ReleaseDir, $ExpectedVersion) {
    $executable = Join-Path $ReleaseDir "codebase-memory-mcp.exe"
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $executable -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    try {
        $versionOutput = & $executable --version 2>$null
    } catch {
        return $false
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    return (Get-CodebaseMemoryVersionFromOutput $versionOutput) -ceq $ExpectedVersion
}

function Invoke-CodebaseMemoryCommand($Executable, $FailureMessage, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function Test-LinkTargetExists($Path, $Target) {
    if (-not $Target) { return (Test-Path -LiteralPath $Path) }
    $resolved = if ([IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path (Split-Path $Path -Parent) $Target }
    return (Test-Path -LiteralPath $resolved)
}

function Remove-DanglingLink($Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    $target = @($item.Target)[0]
    if (-not (Test-LinkTargetExists $Path $target)) { Remove-Item -LiteralPath $Path -Force }
}

function Remove-CodebaseMemoryPiAdapter($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    if ($content.Contains('// Generated by codebase-memory-mcp for pi.') -and
        $content.Contains('// codebase-memory-mcp:start') -and
        $content.Contains('// codebase-memory-mcp:end')) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Repair-CodebaseMemorySkill($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    $frontmatter = [regex]::Match($content, '\A---\r?\n(?<body>.*?)\r?\n---(?=\r?\n|\z)', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontmatter.Success) { return }
    $match = [regex]::Match($frontmatter.Groups['body'].Value, '(?m)^description:\s*([^\r\n]+)\r?$')
    if (-not $match.Success) { return }
    $description = $match.Groups[1].Value.Trim()
    if ($description -notmatch ': ' -or $description.StartsWith("'") -or $description.StartsWith('"')) { return }
    $replacement = "description: '$($description.Replace("'", "''"))'"
    $index = $frontmatter.Groups['body'].Index + $match.Index
    $repaired = $content.Remove($index, $match.Length).Insert($index, $replacement)
    [IO.File]::WriteAllText($Path, $repaired, [Text.UTF8Encoding]::new($false))
}

function Remove-CodebaseMemoryPiSkill($Path) {
    $skill = Join-Path $Path 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $skill
    if ($content.Contains('name: codebase-memory') -and
        $content.Contains('# Codebase Memory — Knowledge Graph Tools') -and
        $content.Contains('## 15 MCP Tools')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Repair-CodebaseMemoryCodexMcp($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    if ($content.Contains('# >>> codebase-memory-mcp MCP >>>')) { return }

    $header = [regex]::Match($content, '(?m)^\[mcp_servers\.codebase-memory-mcp\]\r?$')
    if (-not $header.Success) { return }
    $following = $content.Substring($header.Index + $header.Length)
    $nextHeader = [regex]::Match($following, '(?m)^\[')
    $sectionEnd = if ($nextHeader.Success) { $header.Index + $header.Length + $nextHeader.Index } else { $content.Length }
    $section = $content.Substring($header.Index, $sectionEnd - $header.Index).TrimEnd("`r", "`n")
    if ($section -notmatch '(?m)^\s*command\s*=\s*["''].*codebase-memory-mcp(?:\.exe)?["'']\s*$') { return }
    if ($section -match '(?m)^\s*(?!\[mcp_servers\.codebase-memory-mcp\]\s*$|command\s*=|args\s*=\s*\[\s*\]\s*$|#|$)\S') { return }

    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $managed = "# >>> codebase-memory-mcp MCP >>>${newline}${section}${newline}# <<< codebase-memory-mcp MCP <<<${newline}"
    $repaired = $content.Substring(0, $header.Index) + $managed + $content.Substring($sectionEnd)
    [IO.File]::WriteAllText($Path, $repaired, [Text.UTF8Encoding]::new($false))
}

function Suspend-CodebaseMemoryCodexToolApprovals($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $content = Get-Content -Raw -LiteralPath $Path
    $matches = @([regex]::Matches($content, '(?ms)^\[mcp_servers\.codebase-memory-mcp\.tools\.[^\]\r\n]+\]\r?\n.*?(?=^\[|\z)'))
    if ($matches.Count -eq 0) { return '' }

    $saved = ($matches | ForEach-Object { $_.Value.TrimEnd("`r", "`n") }) -join "`n`n"
    for ($i = $matches.Count - 1; $i -ge 0; $i--) {
        $content = $content.Remove($matches[$i].Index, $matches[$i].Length)
    }
    [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
    return $saved
}

function Restore-CodebaseMemoryCodexToolApprovals($Path, $Approvals) {
    if ([string]::IsNullOrWhiteSpace($Approvals)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $restored = $content.TrimEnd("`r", "`n") + $newline + $newline + ($Approvals -replace "`r?`n", $newline) + $newline
    [IO.File]::WriteAllText($Path, $restored, [Text.UTF8Encoding]::new($false))
}

function Repair-CodebaseMemoryCodexHooks($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    $block = [regex]::new('(?ms)\r?\n?# >>> codebase-memory-mcp SessionStart >>>.*?# <<< codebase-memory-mcp SessionStart <<<\r?\n?')
    $repaired = $block.Replace($content, '', 1)
    if ($repaired -eq $content -or $repaired -notmatch '(?m)^\s*SessionStart\s*=') { return }
    [IO.File]::WriteAllText($Path, $repaired, [Text.UTF8Encoding]::new($false))
}

function Stop-CodebaseMemoryProcesses {
    $processes = @(Get-Process -Name 'codebase-memory-mcp' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return }
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    $processes | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
}

function Test-CodebaseMemoryConfigDatabaseAccess($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        return $true
    } catch {
        $exception = $_.Exception
        while ($exception) {
            if ($exception -is [UnauthorizedAccessException]) { return $false }
            $exception = $exception.InnerException
        }
        throw
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Repair-CodebaseMemoryConfigDatabase($Path) {
    $Path = [IO.Path]::GetFullPath($Path)
    if (Test-CodebaseMemoryConfigDatabaseAccess $Path) { return }

    $escapedPath = $Path.Replace("'", "''")
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $takeown = (Join-Path $env:SystemRoot 'System32\takeown.exe').Replace("'", "''")
    $icacls = (Join-Path $env:SystemRoot 'System32\icacls.exe').Replace("'", "''")
    $command = @(
        "& '$takeown' /F '$escapedPath' | Out-Null"
        'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
        "& '$icacls' '$escapedPath' /reset /Q | Out-Null"
        'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
        "& '$icacls' '$escapedPath' /grant:r '*${sid}:(F)' /Q | Out-Null"
        'exit $LASTEXITCODE'
    ) -join '; '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded) -Verb RunAs -Wait -PassThru
    if ($elevated.ExitCode -ne 0 -or -not (Test-CodebaseMemoryConfigDatabaseAccess $Path)) {
        throw "Elevated codebase-memory config database ACL repair failed: $Path"
    }
}

function Invoke-CodebaseMemoryAgentInstall($Executable) {
    $openCodeRoot = Join-Path $env:USERPROFILE '.config\opencode'
    foreach ($path in (Join-Path $openCodeRoot 'opencode.json'), (Join-Path $openCodeRoot 'AGENTS.md')) {
        Remove-DanglingLink $path
    }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE '.codex' } else { $env:CODEX_HOME }
    $codexConfig = Join-Path $codexHome 'config.toml'
    $toolApprovals = Suspend-CodebaseMemoryCodexToolApprovals $codexConfig
    try {
        Repair-CodebaseMemoryCodexMcp $codexConfig
        Repair-CodebaseMemoryCodexHooks $codexConfig
        Invoke-CodebaseMemoryCommand $Executable 'codebase-memory-mcp agent configuration failed' @('install', '-y')
    } finally {
        Restore-CodebaseMemoryCodexToolApprovals $codexConfig $toolApprovals
        Repair-CodebaseMemoryCodexHooks $codexConfig
        Repair-CodebaseMemorySkill (Join-Path $env:USERPROFILE '.agents\skills\codebase-memory\SKILL.md')
        Remove-CodebaseMemoryPiSkill (Join-Path $env:USERPROFILE '.pi\agent\skills\codebase-memory')
        Remove-CodebaseMemoryPiAdapter (Join-Path $env:USERPROFILE '.pi\agent\extensions\cbmem.ts')
    }
}

function InstallCodebaseMemory {
    param([switch]$Update)
    Info "Installing codebase-memory-mcp..."
    if ($script:Dry) { return }
    if (-not [Environment]::Is64BitOperatingSystem) { throw "codebase-memory-mcp requires 64-bit Windows" }

    $pinsPath = Join-Path $script:DotfilesDir "packages\codebase-memory-mcp-release.json"
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing codebase-memory-mcp pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid pinned codebase-memory-mcp version: $version" }
    $architecture = Get-CodebaseMemoryWindowsArch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
    $asset = $pins.windows.$architecture
    $expectedHash = [string]$asset.sha256
    $assetFile = [string]$asset.file
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') { throw "Invalid pinned codebase-memory-mcp checksum for $architecture" }
    if ($assetFile -notmatch "^codebase-memory-mcp(?:-ui)?-windows-$architecture\.zip$") { throw "Invalid pinned codebase-memory-mcp asset for $architecture" }

    $legacyRoot = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp"
    $releasesRoot = Join-Path $legacyRoot "releases"
    $releaseDir = Join-Path $releasesRoot "$version-windows-$architecture-$($expectedHash.Substring(0, 12))"
    $executable = Join-Path $releaseDir "codebase-memory-mcp.exe"
    New-Item -ItemType Directory -Force -Path $legacyRoot | Out-Null
    $installLock = [IO.File]::Open((Join-Path $legacyRoot "install.lock"), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    try {
        if ((Test-Path -LiteralPath $releaseDir) -and -not (Test-CodebaseMemoryRelease $releaseDir $version)) {
            throw "Pinned codebase-memory-mcp release is incomplete: $releaseDir"
        }
        if (-not (Test-Path -LiteralPath $releaseDir)) {
            New-Item -ItemType Directory -Force -Path $releasesRoot | Out-Null
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) "codebase-memory-install-$([Guid]::NewGuid().ToString('N'))"
            $stagingDir = Join-Path $releasesRoot ".staging.$([Guid]::NewGuid().ToString('N'))"
            $archive = Join-Path $tempDir $assetFile
            $archiveLock = $null
            try {
                New-Item -ItemType Directory -Force -Path $tempDir, $stagingDir | Out-Null
                $uri = "https://github.com/DeusData/codebase-memory-mcp/releases/download/v$version/$assetFile"
                Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
                $archiveLock = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if ((Get-StreamSha256 $archiveLock) -ne $expectedHash) { throw "codebase-memory-mcp package checksum mismatch" }
                if (-not (Test-CodebaseMemoryArchive $archive)) { throw "Unexpected codebase-memory-mcp archive layout" }
                Expand-Archive -LiteralPath $archive -DestinationPath $stagingDir -Force
                if (-not (Test-CodebaseMemoryRelease $stagingDir $version)) { throw "codebase-memory-mcp package is incomplete or has wrong version" }
                $archiveLock.Dispose()
                $archiveLock = $null
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction Stop
                Move-Item -LiteralPath $stagingDir -Destination $releaseDir
            } catch {
                $operationError = $_
                if ($archiveLock) { $archiveLock.Dispose(); $archiveLock = $null }
                $cleanupError = $null
                foreach ($path in $tempDir, $stagingDir) {
                    try {
                        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
                    } catch {
                        if (-not $cleanupError) { $cleanupError = $_.Exception }
                    }
                }
                if ($cleanupError) { throw "codebase-memory cleanup failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
                throw $operationError
            } finally {
                if ($archiveLock) { $archiveLock.Dispose() }
            }
        }

        if (-not (Test-CodebaseMemoryRelease $releaseDir $version)) { throw "Installed codebase-memory-mcp release verification failed" }
        Invoke-CodebaseMemoryAgentInstall $executable
        Stop-CodebaseMemoryProcesses
        Repair-CodebaseMemoryConfigDatabase (Join-Path $env:USERPROFILE '.cache\codebase-memory-mcp\_config.db')
        Invoke-CodebaseMemoryCommand $executable "codebase-memory-mcp auto-index configuration failed" @("config", "set", "auto_index", "true")
        Invoke-CodebaseMemoryCommand $executable "codebase-memory-mcp auto-watch configuration failed" @("config", "set", "auto_watch", "true")
        Set-CodebaseMemoryActivePath $releaseDir $releasesRoot $legacyRoot
    } finally {
        $installLock.Dispose()
    }

    Success "Finished installing codebase-memory-mcp"
}

function SyncAiInstructions {
    Info "Syncing shared agent instructions..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir 'config\shared\ai\AGENTS.md'
    foreach ($target in @(
            (Join-Path $env:USERPROFILE '.codex\AGENTS.md'),
            (Join-Path $env:USERPROFILE '.pi\agent\AGENTS.md')
        )) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Install-SkillDirectory($Source, $Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing vendored skill: $Source" }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'SKILL.md') -PathType Leaf)) { throw "Vendored skill has no SKILL.md: $Source" }
    $sourceItems = @((Get-Item -LiteralPath $Source -Force)) + @(Get-ChildItem -LiteralPath $Source -Recurse -Force)
    $sourceReparsePoint = $sourceItems | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    } | Select-Object -First 1
    if ($sourceReparsePoint) { throw "Vendored skill contains a reparse point: $($sourceReparsePoint.FullName)" }

    $parent = Split-Path $Destination -Parent
    $name = Split-Path $Destination -Leaf
    $staging = Join-Path $parent ".$name.staging.$([Guid]::NewGuid().ToString('N'))"
    $backup = Join-Path $parent ".$name.backup.$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    try {
        Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath (Join-Path $staging 'SKILL.md') -PathType Leaf)) { throw "Staged skill has no SKILL.md: $Source" }
        $reparsePoint = Get-ChildItem -LiteralPath $staging -Recurse -Force | Where-Object {
            $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        } | Select-Object -First 1
        if ($reparsePoint) { throw "Vendored skill contains a reparse point: $($reparsePoint.FullName)" }

        if (Test-Path -LiteralPath $Destination) { Move-Item -LiteralPath $Destination -Destination $backup }
        Move-Item -LiteralPath $staging -Destination $Destination
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop }
    } catch {
        $operationError = $_
        $cleanupError = $null
        try {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $backup) {
                if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction Stop }
                Move-Item -LiteralPath $backup -Destination $Destination -ErrorAction Stop
            }
        } catch {
            $cleanupError = $_.Exception
        }
        if ($cleanupError) { throw "Skill rollback failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
        throw $operationError
    }
}

function InstallAiSkills {
    Info "Installing shared agent skills..."
    if ($script:Dry) { return }

    $sourceRoot = Join-Path $script:DotfilesDir 'config\shared\ai\skills'
    $targetRoot = Join-Path $env:USERPROFILE '.agents\skills'
    $skills = @('caveman', 'systematic-debugging', 'test-driven-development', 'verification-before-completion', 'diff-review-qa', 'ponytail', 'ponytail-audit', 'ponytail-debt', 'ponytail-gain', 'ponytail-help', 'ponytail-review')
    foreach ($skill in $skills) {
        Install-SkillDirectory (Join-Path $sourceRoot $skill) (Join-Path $targetRoot $skill)
        Remove-Item -LiteralPath (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill") -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Install or update agent CLIs and their shared skills.
function InstallAi {
    param([switch]$Update)
    Info "Installing agent CLIs..."
    if ($script:Dry) { return }

    InstallCodex -Update:$Update

    InstallCodebaseMemory -Update:$Update
    InstallFffMcp -Update:$Update
    SyncCodexConfig
    InstallPi -Update:$Update
    InstallPiLanguageServers -Update:$Update
    InstallPiExtensions
    SyncPiConfigs
    if ($Update) {
        Invoke-NativeChecked "Pi extension reconciliation failed" { pi update --extensions }
    }
    SyncAiInstructions
    InstallAiSkills

    Success "Finished installing agent CLIs and skills"
}

function Get-NeovimCommand {
    $command = Get-Command nvim -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $wingetLink = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nvim.exe"
    if (Test-Path -LiteralPath $wingetLink) { return $wingetLink }

    $programFiles = Join-Path $env:ProgramFiles "Neovim\bin\nvim.exe"
    if (Test-Path -LiteralPath $programFiles) { return $programFiles }

    $wingetPackages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $installed = Get-ChildItem -Path $wingetPackages -Filter nvim.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installed) { return $installed.FullName }
    return $null
}

function Get-NeovimDataPath($nvim) {
    $output = & $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" "+qa" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($output -join '').Trim())
}

function Sync-NeovimPlugins {
    Info "Installing or updating Neovim plugins..."
    if ($script:Dry) { return }

    try {
        $nvim = Get-NeovimCommand
        if (-not $nvim) { throw "nvim executable not found" }
        & $nvim --headless "+Lazy! restore" "+qa" 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Neovim plugin sync failed; Neovim may finish setup on first start"
        } else {
            $dataPath = Get-NeovimDataPath $nvim
            if (-not $dataPath) { throw "could not determine Neovim data path" }
            $lazyRoot = Join-Path $dataPath "lazy"
            if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot "lazy.nvim")) -or
                -not (Test-Path -LiteralPath (Join-Path $lazyRoot "snacks.nvim"))) {
                Write-Warning "Neovim plugin sync did not install lazy.nvim and snacks.nvim; Neovim may finish setup on first start"
            }
        }
    } catch {
        Write-Warning "Neovim plugin sync failed; Neovim may finish setup on first start: $_"
    }
}

function Invoke-UpdatedDotfile($CommandName, $Target = '') {
    $scriptPath = Join-Path $script:DotfilesDir 'dotfile.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Updated dotfile script not found: $scriptPath" }
    $arguments = @('-NoProfile', '-File', $scriptPath, '-AfterUpdate')
    if ($script:Dry) { $arguments += '-Dry' }
    if ($script:Force) { $arguments += '-Force' }
    if ($script:Quiet) { $arguments += '-Quiet' }
    $arguments += $CommandName
    if ($Target) { $arguments += $Target }

    $previousSentinel = $env:DOTFILE_AFTER_UPDATE
    try {
        $env:DOTFILE_AFTER_UPDATE = '1'
        & (Get-Process -Id $PID).Path @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousSentinel) {
            Remove-Item Env:DOTFILE_AFTER_UPDATE -ErrorAction SilentlyContinue
        } else {
            $env:DOTFILE_AFTER_UPDATE = $previousSentinel
        }
    }
    if ($exitCode -ne 0) { throw "Updated dotfile process failed with exit code $exitCode" }
}

function Update-Packages($Target = '', [switch]$AfterRepoUpdate) {
    if ($Target -and $Target -ne 'ai') { Fail "Unknown update target: $Target" }
    $aiOnly = $Target -eq 'ai'
    Info $(if ($aiOnly) { "Updating AI tools and configs..." } else { "Updating packages..." })
    if (-not $AfterRepoUpdate) {
        UpdateRepo
        Invoke-UpdatedDotfile 'update' $Target
        return
    }

    if ($aiOnly) {
        InstallAi -Update
    } else {
        InstallPackages
        InstallExtras -Update
        InstallAi -Update
        SetupSymlinks
        Sync-NeovimPlugins
    }
    if (-not $script:Dry) { Assert-WindowsHealthy }
    Success $(if ($aiOnly) { "Finished AI update" } else { "Finished updating packages" })
}

function AddToUserPath($dir) {
    Info "Ensuring $dir is on user PATH"
    if ($script:Dry) { return }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @()
    if ($userPath) { $entries = $userPath.Split(';') | Where-Object { $_ -ne "" } }
    if ($entries -contains $dir) {
        Success "$dir already on user PATH"
    } else {
        $newPath = (($entries + $dir) -join ';')
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Success "Added $dir to user PATH"
    }

    if (-not ($env:Path.Split(';') -contains $dir)) {
        $env:Path = "$env:Path;$dir"
    }
}

function New-LinkSpec($Kind, $Source, $Destination, [bool]$AddToPath = $false) {
    [pscustomobject]@{
        Kind = $Kind
        Source = $Source
        Destination = $Destination
        AddToPath = $AddToPath
    }
}

function Get-WindowsLinkSpecs {
    $configPath = Join-Path $script:DotfilesDir "config\windows"
    $sharedPath = Join-Path $script:DotfilesDir "config\shared"

    # Use $env:USERPROFILE rather than $HOME so test fixtures can override the
    # home directory by setting the env var. PowerShell's $HOME automatic
    # variable is read-only and frozen at session start, so $HOME would always
    # resolve to the real home — leaking test artifacts into ~/Documents etc.
    $userHome = $env:USERPROFILE
    $specs = @()

    # PowerShell profiles (link each file into the target dir).
    $psSource = Join-Path $configPath "Powershell"
    $targets = @(
        "$userHome\Documents\WindowsPowerShell"
        "$userHome\Documents\PowerShell"
    )
    foreach ($target in $targets) {
        Get-ChildItem $psSource -File | ForEach-Object {
            $specs += New-LinkSpec 'File' $_.FullName (Join-Path $target $_.Name)
        }
    }

    # Windows Terminal settings
    $specs += New-LinkSpec 'File' `
        (Join-Path $configPath "Terminal\settings.json") `
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    # Git config
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".gitconfig") "$userHome\.gitconfig"
    $specs += New-LinkSpec 'File' (Join-Path $configPath ".gitconfig") "$userHome\.gitconfig.windows"

    # SSH and GnuPG configs
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".ssh\config") "$userHome\.ssh\config"
    $specs += New-LinkSpec 'File' (Join-Path $configPath ".gnupg\gpg-agent.conf") (Join-Path $env:APPDATA "gnupg\gpg-agent.conf")

    # Notepad++ settings: keep runtime-written config.xml writable.
    $notepadSource = Join-Path $configPath "Notepad++"
    $notepadTarget = Join-Path $env:APPDATA "Notepad++"
    foreach ($name in "contextMenu.xml", "shortcuts.xml") {
        $specs += New-LinkSpec 'File' (Join-Path $notepadSource $name) (Join-Path $notepadTarget $name)
    }
    Get-ChildItem (Join-Path $notepadSource "themes") -File | ForEach-Object {
        $specs += New-LinkSpec 'File' $_.FullName (Join-Path $notepadTarget "themes\$($_.Name)")
    }

    # Neovim settings: keep plugin manager state writable.
    $nvimSource = Join-Path $sharedPath "config\nvim"
    $nvimTarget = "$env:LOCALAPPDATA\nvim"
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "init.lua") (Join-Path $nvimTarget "init.lua")
    $specs += New-LinkSpec 'Dir' (Join-Path $nvimSource "lua") (Join-Path $nvimTarget "lua")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource ".gitignore") (Join-Path $nvimTarget ".gitignore")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "stylua.toml") (Join-Path $nvimTarget "stylua.toml")

    # Jujutsu config (lives at %APPDATA%\jj\config.toml on Windows)
    $specs += New-LinkSpec 'Dir' (Join-Path $sharedPath "config\jj") "$env:APPDATA\jj"

    # starship prompt config — shared with zsh, read from ~/.config/starship.toml.
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath "config\starship.toml") (Join-Path $userHome ".config\starship.toml")

    # Link the repo-root dotfile.ps1 entry point into a user PATH directory.
    $binDest = "$userHome\.local\bin"
    $specs += New-LinkSpec 'File' (Join-Path $script:DotfilesDir "dotfile.ps1") (Join-Path $binDest "dotfile.ps1") $true

    return $specs
}

function Sync-NotepadPlusPlusConfig {
    Info "Syncing writable Notepad++ configuration..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir "config\windows\Notepad++\config.xml"
    $target = Join-Path $env:APPDATA "Notepad++\config.xml"
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    (Get-Item -LiteralPath $target).IsReadOnly = $false
}

function Migrate-WindowsNvimConfig {
    if ($script:Dry) { return }
    $destination = "$env:LOCALAPPDATA\nvim"
    if (-not (Test-Path -LiteralPath $destination)) { return }

    $item = Get-Item -LiteralPath $destination -Force
    if (-not $item.LinkType) { return }

    $legacySource = Join-Path $script:DotfilesDir "config\shared\config\nvim"
    if ($item.Target -ne $legacySource) {
        throw "Neovim config points to unexpected target: $($item.Target)"
    }
    Remove-Item -LiteralPath $destination -Force
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

function Sync-LazyLock {
    Info "Syncing writable Neovim plugin lock..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir "config\shared\config\nvim\lazy-lock.json"
    $target = "$env:LOCALAPPDATA\nvim\lazy-lock.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $source -Destination $target
    (Get-Item -LiteralPath $target).IsReadOnly = $false
}

function SetupSymlinks {
    Info "Setting up symlinks..."
    $script:OverwriteAll = $script:Force
    $script:BackupAll = $false
    $script:SkipAll = $false
    Migrate-WindowsNvimConfig

    foreach ($spec in Get-WindowsLinkSpecs) {
        if ($spec.AddToPath) {
            AddToUserPath (Split-Path $spec.Destination -Parent)
        }
        LinkPath -source $spec.Source -destination $spec.Destination -isDirectory ($spec.Kind -eq 'Dir')
    }
    Sync-NotepadPlusPlusConfig
    Sync-LazyLock
    if (-not $script:Dry) {
        $gpgconf = Join-Path $env:ProgramFiles 'GnuPG\bin\gpgconf.exe'
        Invoke-NativeChecked "GPG agent reload failed" { & $gpgconf --reload gpg-agent }
    }

    Success "Finished setting up symlinks"
}

function Verify {
    $errors = 0

    Info "Verifying installed tools..."
    foreach ($cmd in Get-RequiredCommands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            Success "$cmd found: $($found.Source)"
        } else {
            FailSoft "$cmd not found"
            $errors++
        }
    }

    Info "Verifying Winget packages..."
    foreach ($id in Get-WingetPackages) {
        if (WingetHas $id) {
            Success "Winget package: $id"
        } else {
            FailSoft "Winget package missing: $id"
            $errors++
        }
    }

    Info "Verifying scoop packages..."
    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if ($scoopExists) {
        Success "scoop installed"
        $installedScoopPackages = @(scoop list)
        if ($LASTEXITCODE -ne 0) {
            FailSoft "scoop package list failed"
            $errors++
        } else {
            foreach ($name in Get-ScoopPackages) {
                if ($installedScoopPackages.Name -contains $name) {
                    Success "Scoop package: $name"
                } else {
                    FailSoft "Scoop package missing: $name"
                    $errors++
                }
            }
        }
    } else {
        FailSoft "scoop not installed"
        $errors++
    }

    Info "Verifying PowerShell modules..."
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Success "PowerShell module: PSReadLine"
    } else {
        FailSoft "PowerShell module missing: PSReadLine"
        $errors++
    }

    Info "Verifying managed links..."
    foreach ($file in Get-WindowsLinkSpecs) {
        if (-not (Test-Path -LiteralPath $file.Destination)) {
            FailSoft "$($file.Destination) not found"
            $errors++
            continue
        }
        $item = Get-Item -LiteralPath $file.Destination -Force
        if ($item.Target -eq $file.Source) {
            Success "$($file.Destination) -> $($file.Source)"
        } else {
            FailSoft "$($file.Destination) is not linked to $($file.Source)"
            $errors++
        }
    }

    Info "Verifying neovim config..."
    $nvimPath = "$env:LOCALAPPDATA\nvim"
    if (Test-Path (Join-Path $nvimPath "init.lua")) {
        Success "Neovim config installed"
    } else {
        FailSoft "Neovim config not found at $nvimPath"
        $errors++
    }

    Info "Verifying Codex config..."
    $codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $codexConfig)) {
        FailSoft "$codexConfig not found"
        $errors++
    } elseif (($item = Get-Item -LiteralPath $codexConfig -Force).PSIsContainer -or
        $item.LinkType -or $item.IsReadOnly) {
        FailSoft "$codexConfig must be a regular writable file"
        $errors++
    } else {
        Success "Codex config installed"
    }

    Write-Host ""
    if ($errors -eq 0) {
        $script:VerifyFailed = $false
        Success "All checks passed!"
    } else {
        $script:VerifyFailed = $true
        Info "$errors issue(s) found"
    }
}

function Doctor {
    Refresh-ProcessPath
    Verify
}

function Assert-WindowsHealthy {
    $callerPath = $env:Path
    try {
        Doctor
    } finally {
        $env:Path = $callerPath
    }
    if ($script:VerifyFailed) { throw "Windows installation verification failed" }
}

function SetupDotfiles([switch]$AfterRepoUpdate) {
    Info "Setting up dotfiles..."
    if (-not $AfterRepoUpdate) {
        UpdateRepo
        Invoke-UpdatedDotfile 'all'
        return
    }

    InstallManagedPackages
    SetupSymlinks
    Sync-NeovimPlugins
    if (-not $script:Dry) { Assert-WindowsHealthy }
    Success "Done!"
}

function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Update system packages
              Update only AI tools and configs with update ai
  packages    Install all managed packages only
  ai          Install AI tools and shared skills
  doctor      Detect Windows installation issues
  verify      Verify installation

Options:
  -d, --dry     Dry run (no changes made)
  -f, --force   Overwrite existing files without prompting
  -q, --quiet   Only show errors
  -h, --help    Show this help message
"@
}

if (-not $NoMain) {
    if ($AfterUpdate -and $env:DOTFILE_AFTER_UPDATE -ne '1') { Fail "-AfterUpdate is internal and requires the parent updater" }
    if ($Help) { ShowUsage; exit 0 }
    if ($UpdateTarget -and $Command -ne 'update') { Fail "Unexpected argument after ${Command}: $UpdateTarget" }

    switch ($Command) {
        "all"       { SetupDotfiles -AfterRepoUpdate:$AfterUpdate }
        "update"    { Update-Packages $UpdateTarget -AfterRepoUpdate:$AfterUpdate }
        "packages"  { InstallManagedPackages }
        "ai"        { InstallAi }
        "doctor"    { Doctor; if ($script:VerifyFailed) { exit 1 } }
        "verify"    { Verify; if ($script:VerifyFailed) { exit 1 } }
        default     { Fail "Unknown command: $Command" }
    }
}
