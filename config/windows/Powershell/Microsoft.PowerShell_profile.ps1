if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Aliases (parity with .zshrc.base)
. "$PSScriptRoot\aliases.ps1"

# PSReadLine Options (PSReadLine auto-loads in interactive pwsh)
try {
    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
} catch {
}

# fnm
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
$managedPi = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\bin'
$env:Path = (@($managedPi) + @($env:Path -split ';' | Where-Object { $_ -and $_ -ine $managedPi })) -join ';'

# zoxide — bind it to `cd` (mirrors the unix .zshrc)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell --cmd cd | Out-String | Invoke-Expression
}

# jj (jujutsu) completion — dynamic mode
if (Get-Command jj -ErrorAction SilentlyContinue) {
    $previousComplete = [Environment]::GetEnvironmentVariable('COMPLETE', 'Process')
    try {
        $env:COMPLETE = "powershell"
        jj | Out-String | Invoke-Expression
    } finally {
        if ($null -eq $previousComplete) {
            Remove-Item Env:\COMPLETE -ErrorAction SilentlyContinue
        } else {
            $env:COMPLETE = $previousComplete
        }
    }
}

function Enter-PsmuxMainSession {
    if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) { return }

    psmux attach -t main 2>$null
    if ($LASTEXITCODE -ne 0) { psmux new-session -s main }
}

# Match the Unix tmux autostart without intercepting scripts, nested panes, or
# embedded terminals. Set NO_TMUX=1 before launching pwsh for an explicit opt-out.
$nonInteractiveArgs = '-Command', '-c', '-File', '-f', '-EncodedCommand', '-e', '-NonInteractive'
$processArgs = [Environment]::GetCommandLineArgs()
$startsPsmux = $Host.Name -eq 'ConsoleHost' `
    -and -not [Console]::IsInputRedirected `
    -and -not [Console]::IsOutputRedirected `
    -and -not ($processArgs | Where-Object { $_ -in $nonInteractiveArgs }) `
    -and -not $env:TMUX `
    -and -not $env:PSMUX_ACTIVE `
    -and -not $env:NO_TMUX `
    -and $env:TERM_PROGRAM -ne 'vscode' `
    -and -not $env:VSCODE_PID `
    -and -not $env:INSIDE_EMACS `
    -and -not $env:VIMRUNTIME
if ($startsPsmux) { Enter-PsmuxMainSession }
