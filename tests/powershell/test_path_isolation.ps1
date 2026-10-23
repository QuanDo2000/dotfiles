# Safety guard: ordinary fixtures must never call native User persistence,
# even during setup/cleanup. Native registry integration belongs only in an
# explicitly disposable Windows account, outside ordinary test discovery.
function test_ordinary_fixtures_do_not_write_native_user_environment {
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
        if ($file.Name -like 'integration_*') { continue }
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        $writes = $ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Static -and $node.Member.Value -eq 'SetEnvironmentVariable' -and
            $node.Arguments.Count -eq 3 -and $node.Arguments[2].Extent.Text -match 'User'
        }, $true)
        Assert-Equals 0 @($writes).Count
    }
}

function test_native_user_path_writes_are_confined_to_mocked_boundary {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($script:DotfileScript, [ref]$tokens, [ref]$parseErrors)
    $writes = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Static -and $node.Member.Value -eq 'SetEnvironmentVariable'
    }, $true)
    foreach ($write in $writes) {
        $owner = $write.Parent
        while ($owner -and $owner -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
        Assert-Equals 'Set-UserPath' $owner.Name
    }
    # These calls exercise the installed mocks without consulting the account.
    Set-UserPath 'C:\test-only'
    Assert-Equals 'C:\test-only' (Get-UserPath)
}
