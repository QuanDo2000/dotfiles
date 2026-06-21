Invoke-Expression (&starship init powershell)

# PSReadLine Options
Import-Module Terminal-Icons
Import-Module PSReadLine
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function Complete

# fnm
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

# jj (jujutsu) completion — dynamic mode
if (Get-Command jj -ErrorAction SilentlyContinue) {
    $env:COMPLETE = "powershell"
    jj | Out-String | Invoke-Expression
    Remove-Item Env:\COMPLETE
}
