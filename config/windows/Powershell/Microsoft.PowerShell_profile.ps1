Invoke-Expression (&starship init powershell)

# PSReadLine Options (PSReadLine auto-loads in interactive pwsh)
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function Complete

# fnm
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

# zoxide — bind it to `cd` (mirrors the unix .zshrc)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })
}

# jj (jujutsu) completion — dynamic mode
if (Get-Command jj -ErrorAction SilentlyContinue) {
    $env:COMPLETE = "powershell"
    jj | Out-String | Invoke-Expression
    Remove-Item Env:\COMPLETE
}
