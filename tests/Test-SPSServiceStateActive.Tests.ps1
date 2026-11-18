# Tests for Test-SPSServiceStateActive: does a service state file belong to an update that is running?

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Private/Test-SPSServiceStateActive.ps1')

    $script:TmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsupd-active-' + [guid]::NewGuid())
    New-Item -Path $script:TmpDir -ItemType Directory -Force | Out-Null
    $script:Start = [datetime]'2026-11-18T10:00:00'
    $script:Other = $PID + 1

    function New-State {
        param($Owner, $OwnerStart)
        $path = Join-Path -Path $script:TmpDir -ChildPath ('state-' + [guid]::NewGuid() + '.json')
        $state = [ordered]@{ Computer = 'X'; IisReset = $false; Services = @() }
        if ($null -ne $Owner) { $state['ProcessId'] = $Owner }
        if ($null -ne $OwnerStart) { $state['ProcessStart'] = $OwnerStart }
        $state | ConvertTo-Json -Depth 3 | Set-Content -Path $path
        return $path
    }
}

AfterAll {
    if ($script:TmpDir -and (Test-Path $script:TmpDir)) { Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Test-SPSServiceStateActive' {
    It 'is active when another process that started at the recorded time still runs' {
        Mock Get-Process { [pscustomobject]@{ Id = $script:Other; StartTime = $script:Start } }
        Test-SPSServiceStateActive -Path (New-State -Owner $script:Other -OwnerStart $script:Start.ToString('o')) | Should -BeTrue
    }

    It 'is a leftover when the owner process is gone' {
        Mock Get-Process { $null }
        Test-SPSServiceStateActive -Path (New-State -Owner $script:Other -OwnerStart $script:Start.ToString('o')) | Should -BeFalse
    }

    It 'is a leftover when the process id was reused by a process that started at another time' {
        Mock Get-Process { [pscustomobject]@{ Id = $script:Other; StartTime = $script:Start.AddHours(3) } }
        Test-SPSServiceStateActive -Path (New-State -Owner $script:Other -OwnerStart $script:Start.ToString('o')) | Should -BeFalse
    }

    It 'is not active for the process that asks (its own file)' {
        Mock Get-Process { [pscustomobject]@{ Id = $PID; StartTime = $script:Start } }
        Test-SPSServiceStateActive -Path (New-State -Owner $PID -OwnerStart $script:Start.ToString('o')) | Should -BeFalse
    }

    It 'is a leftover when the file has no owner (written by an earlier version)' {
        Mock Get-Process { [pscustomobject]@{ Id = $script:Other; StartTime = $script:Start } }
        Test-SPSServiceStateActive -Path (New-State) | Should -BeFalse
    }

    It 'is a leftover when the file cannot be read' {
        $bad = Join-Path -Path $script:TmpDir -ChildPath 'bad.json'
        'not json {' | Set-Content -Path $bad
        Test-SPSServiceStateActive -Path $bad | Should -BeFalse
    }

    It 'is active when the owner runs and no start time was recorded' {
        Mock Get-Process { [pscustomobject]@{ Id = $script:Other; StartTime = $script:Start } }
        Test-SPSServiceStateActive -Path (New-State -Owner $script:Other) | Should -BeTrue
    }
}
