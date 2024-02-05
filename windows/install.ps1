
function CopyWithBackup($source, $destination) {
    if (!(Test-Path $destination)) {
        Copy-Item -Path $source -Destination $destination
    }
    else {
        Copy-Item -Path $destination -Destination "$destination.bak"
        Copy-Item -Path $source -Destination $destination -Force
    }
}

function InstallPackages() {
    winget install Microsoft.Powershell Git.Git sharkdp.fd BurntSushi.ripgrep.MSVC fzf JanDeDobbeleer.OhMyPosh vim.vim Microsoft.VisualStudioCode Microsoft.WindowsTerminal --disable-interactivity --accept-package-agreements

    Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force
    Install-Module -Name PSReadLine -Scope CurrentUser -Force
    Install-Module -Name PSFzf

    Update-Module
}

function InstallFont {
    $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
    Write-Host "Please install FiraCode from $url. Please install both Regular and MonoRegular version."
}

function CloneRepo() {
    $repo = "https://github.com/QuanDo2000/dotfiles.git"
    $destination = "$HOME\Documents\Projects\dotfiles"
    Write-Host "Cloning $repo to $destination..."

    if (!(Test-Path $destination)) {
        git clone $repo $destination
    }
    else {
        git -C $destination pull
    }
    Write-Host "Done."
}

function SyncSettings() {
    Write-Host "Syncing settings..."
    $configPath = "$HOME\Documents\Projects\dotfiles\windows"

    $targets = @(
        "$HOME\Documents\WindowsPowerShell"
        "$HOME\Documents\PowerShell"
    )

    foreach ($target in $targets) {
        if (!(Test-Path $target)) {
            New-Item -ItemType Directory -Path $target
        }
    }

    foreach ($target in $targets) {
        Write-Host "Syncing to $target..."
        Get-ChildItem -Path $configPath\Powershell -File | ForEach-Object {
            $file = $_
            $filename = $_.Name
            $destination = "$target\$filename"
            CopyWithBackup -source $file -destination $destination
        }
    }

    Write-Host "Syncing Terminal settings..."
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettingsSource = "$configPath\Terminal\settings.json"
    CopyWithBackup -source $terminalSettingsSource -destination $terminalSettingsPath

    Write-Host "Syncing Vim settings..."
    CopyWithBackup -source "$configPath\_vimrc" -destination "$HOME\_vimrc"
    CopyWithBackup -source "$configPath\_gvimrc" -destination "$HOME\_gvimrc"
    Write-Host "Done."
}

InstallPackages
InstallFont
CloneRepo
SyncSettings
