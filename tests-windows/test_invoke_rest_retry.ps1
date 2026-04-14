# InvokeRestMethodRetry: success, retry-then-success, retry-exhausted.
# Mock Invoke-RestMethod by shadowing it with a function; it beats the cmdlet
# in command resolution order.

function TestSetup {
    $script:Quiet = $true  # silence retry log messages during tests
}

function TestTeardown {
    Clear-CommandMock 'Invoke-RestMethod'
    Remove-Variable -Name 'RestCallCount' -Scope Global -ErrorAction SilentlyContinue
}

function test_rest_retry_succeeds_first_attempt {
    $global:RestCallCount = 0
    Set-CommandMock 'Invoke-RestMethod' {
        $global:RestCallCount++
        return @{ ok = $true }
    }

    $result = InvokeRestMethodRetry -Uri 'http://example.com'

    Assert-Equals 1 $global:RestCallCount
    Assert-True $result.ok 'result.ok should be true'
}

function test_rest_retry_succeeds_after_one_failure {
    $global:RestCallCount = 0
    Set-CommandMock 'Invoke-RestMethod' {
        $global:RestCallCount++
        if ($global:RestCallCount -lt 2) { throw 'transient' }
        return @{ ok = $true }
    }

    # MaxAttempts=2 with Start-Sleep still runs — keep delay short via low value.
    $result = InvokeRestMethodRetry -Uri 'http://example.com' -MaxAttempts 2

    Assert-Equals 2 $global:RestCallCount
    Assert-True $result.ok 'result.ok should be true'
}

function test_rest_retry_throws_after_max_attempts {
    $global:RestCallCount = 0
    Set-CommandMock 'Invoke-RestMethod' {
        $global:RestCallCount++
        throw 'permanent'
    }

    $caught = $false
    try {
        InvokeRestMethodRetry -Uri 'http://example.com' -MaxAttempts 2
    } catch {
        $caught = $true
        Assert-Contains $_.Exception.Message 'permanent'
    }

    Assert-True $caught 'should have thrown after max attempts'
    Assert-Equals 2 $global:RestCallCount
}
