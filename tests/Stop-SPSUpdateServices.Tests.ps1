# Tests for Stop-SPSUpdateServices (service shutdown profiles, state file, role awareness, recovery).
# Services are simulated with a hashtable so the tests run cross-platform.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:StopPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Stop-SPSUpdateServices.ps1'
    $script:RestorePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Restore-SPSUpdateServices.ps1'
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Private/Get-SPSServiceStatePath.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Private/Test-SPSServiceStateActive.ps1')
    . $script:StopPath
    . $script:RestorePath

    # Stubs so the tests run without SharePoint / Windows services.
    function Get-Service { [CmdletBinding()] param([string] $Name) }
    function Set-Service { [CmdletBinding()] param([string] $Name, [string] $StartupType) }
    function Stop-Service { [CmdletBinding()] param([string] $Name, [switch] $Force) }
    function Start-Service { [CmdletBinding()] param([string] $Name) }
    function Add-SPSUpdateEvent { [CmdletBinding()] param([string] $Message, [string] $Source, [string] $EntryType) }
    function Use-SPCacheCluster { }
    function Stop-AFCacheHost { [CmdletBinding()] param([switch] $Graceful, [string] $ComputerName, [int] $CachePort) }
    function Remove-SPDistributedCacheServiceInstance { [CmdletBinding()] param() }
    function Add-SPDistributedCacheServiceInstance { [CmdletBinding()] param() }
    function Get-SPServiceInstance { [CmdletBinding()] param([string] $Server) }

    $script:TmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsupd-svc-' + [guid]::NewGuid())
    New-Item -Path $script:TmpDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if ($script:TmpDir -and (Test-Path $script:TmpDir)) { Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Stop-SPSUpdateServices' {
    BeforeEach {
        $script:Folder = Join-Path -Path $script:TmpDir -ChildPath ([guid]::NewGuid().ToString('N'))
        $script:Calls = New-Object System.Collections.ArrayList
        $script:StateExistedAtFirstStop = $null
        $script:AttemptRecordedBeforeGraceful = $null
        $script:Svc = [ordered]@{
            SPTimerV4              = @{ StartType = 'Automatic'; Status = 'Running' }
            SPTraceV4              = @{ StartType = 'Automatic'; Status = 'Running' }
            SPAdminV4              = @{ StartType = 'Automatic'; Status = 'Running' }
            W3SVC                  = @{ StartType = 'Automatic'; Status = 'Running' }
            IISADMIN               = @{ StartType = 'Automatic'; Status = 'Running' }
            OSearch16              = @{ StartType = 'Manual'; Status = 'Running' }
            SPSearchHostController = @{ StartType = 'Automatic'; Status = 'Running' }
            SPCache                = @{ StartType = 'Automatic'; Status = 'Running' }
        }
        Mock Get-Service {
            if ($script:Svc.Contains($Name)) { [pscustomobject]@{ Name = $Name; StartType = $script:Svc[$Name].StartType; Status = $script:Svc[$Name].Status } }
        }
        Mock Set-Service { $script:Svc[$Name].StartType = $StartupType; [void]$script:Calls.Add("set:${Name}:$StartupType") }
        Mock Stop-Service {
            if ($null -eq $script:StateExistedAtFirstStop) { $script:StateExistedAtFirstStop = @(Get-ChildItem -Path $script:Folder -Filter 'SPSUpdate-ServicesState_*.json').Count -gt 0 }
            $script:Svc[$Name].Status = 'Stopped'; [void]$script:Calls.Add("stop:$Name")
        }
        Mock Start-Service { $script:Svc[$Name].Status = 'Running'; [void]$script:Calls.Add("start:$Name") }
        Mock Start-Process { [void]$script:Calls.Add("process:$FilePath $ArgumentList"); [pscustomobject]@{ ExitCode = 0 } }
        Mock Add-SPSUpdateEvent { }
        Mock Use-SPCacheCluster { }
        Mock Stop-AFCacheHost {
            $file = @(Get-ChildItem -Path $script:Folder -Filter 'SPSUpdate-ServicesState_*.json')[0]
            $cache = (Get-Content -Path $file.FullName -Raw | ConvertFrom-Json).Services | Where-Object Name -eq 'SPCache'
            $script:AttemptRecordedBeforeGraceful = [bool]$cache.GracefulAttempted
            [void]$script:Calls.Add('graceful-stop')
        }
        Mock Remove-SPDistributedCacheServiceInstance { [void]$script:Calls.Add('remove-dcache') }
        Mock Add-SPDistributedCacheServiceInstance { [void]$script:Calls.Add('add-dcache') }
        Mock Get-SPServiceInstance { [pscustomobject]@{ TypeName = 'Distributed Cache' } }
    }

    It 'Basic keeps the historical service list and order, then stops IIS' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Basic -StateFolder $script:Folder

        @($script:Calls | Where-Object { $_ -like 'stop:*' }) | Should -Be @('stop:SPSearchHostController', 'stop:SPTimerV4', 'stop:IISADMIN', 'stop:OSearch16')
        $script:Calls | Should -Contain 'set:SPTimerV4:Disabled'
        $script:Calls | Should -Contain 'process:iisreset.exe -stop -noforce'
        $r.Services | Should -Be @('SPSearchHostController', 'SPTimerV4', 'IISADMIN', 'OSearch16')
    }

    It 'defaults to the Basic profile' {
        $null = Stop-SPSUpdateServices -StateFolder $script:Folder
        $script:Calls | Should -Contain 'process:iisreset.exe -stop -noforce'
        $script:Calls | Should -Not -Contain 'stop:W3SVC'
    }

    It 'Extended stops the full ordered list and does not use iisreset' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder

        @($script:Calls | Where-Object { $_ -like 'stop:*' }) | Should -Be @('stop:SPTimerV4', 'stop:SPTraceV4', 'stop:SPAdminV4', 'stop:W3SVC', 'stop:OSearch16', 'stop:SPSearchHostController', 'stop:SPCache')
        @($script:Calls | Where-Object { $_ -like 'process:*' }).Count | Should -Be 0
        $r.Services.Count | Should -Be 7
    }

    It 'Extended follows the server role: only installed and running services are touched' {
        # Front-end without search nor Distributed Cache, with SPTraceV4 already stopped.
        foreach ($n in 'OSearch16', 'SPSearchHostController', 'SPCache', 'IISADMIN') { $script:Svc.Remove($n) }
        $script:Svc['SPTraceV4'].Status = 'Stopped'

        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder

        @($script:Calls | Where-Object { $_ -like 'stop:*' }) | Should -Be @('stop:SPTimerV4', 'stop:SPAdminV4', 'stop:W3SVC')
        $script:Calls | Should -Not -Contain 'set:SPTraceV4:Disabled'
        $r.Services | Should -Be @('SPTimerV4', 'SPAdminV4', 'W3SVC')
    }

    It 'Extended does nothing and writes no state file when no service is running' {
        foreach ($n in @($script:Svc.Keys)) { $script:Svc[$n].Status = 'Stopped' }
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder

        $r.Path | Should -BeNullOrEmpty
        @($script:Calls).Count | Should -Be 0
        @(Get-ChildItem -Path $script:Folder -Filter '*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'saves the original state BEFORE the first service is stopped' {
        $null = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder
        $script:StateExistedAtFirstStop | Should -BeTrue
    }

    It 'writes the state file at the path given by the caller, and leaves no temporary file behind' {
        $path = Join-Path -Path $script:Folder -ChildPath 'SPSUpdate-ServicesState_CALLER_20260101000000000.json'
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder -StatePath $path

        $r.Path | Should -Be $path
        Test-Path -Path $path | Should -BeTrue
        @(Get-ChildItem -Path $script:Folder -Filter '*.tmp').Count | Should -Be 0
        { Get-Content -Path $path -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'stores the original startup type and status, in restore order (reversed for Extended)' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        @($state.Services.Name) | Should -Be @('SPCache', 'SPSearchHostController', 'OSearch16', 'W3SVC', 'SPAdminV4', 'SPTraceV4', 'SPTimerV4')
        ($state.Services | Where-Object Name -eq 'OSearch16').StartType | Should -Be 'Manual'
        ($state.Services | Where-Object Name -eq 'OSearch16').Status | Should -Be 'Running'
        $state.IisReset | Should -BeFalse
    }

    It 'Basic stores the services in the historical order and flags the IIS restart' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Basic -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        @($state.Services.Name) | Should -Be @('SPSearchHostController', 'SPTimerV4', 'IISADMIN', 'OSearch16')
        $state.IisReset | Should -BeTrue
    }

    It 'records the intention to remove the Distributed Cache BEFORE the destructive calls' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -GracefulStopDistributedCache $true -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        $script:AttemptRecordedBeforeGraceful | Should -BeTrue
        $script:Calls | Should -Contain 'graceful-stop'
        $script:Calls | Should -Contain 'remove-dcache'
        $script:Calls | Should -Not -Contain 'stop:SPCache'
        ($state.Services | Where-Object Name -eq 'SPCache').GracefulAttempted | Should -BeTrue
    }

    It 'falls back to a normal SPCache stop when the graceful stop fails, and keeps the attempt in the state' {
        Mock Stop-AFCacheHost { throw 'cluster unhealthy' }
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -GracefulStopDistributedCache $true -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        $script:Calls | Should -Contain 'stop:SPCache'
        $script:Calls | Should -Not -Contain 'remove-dcache'
        ($state.Services | Where-Object Name -eq 'SPCache').GracefulAttempted | Should -BeTrue
        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Warning' -and $Message -like '*Graceful stop*' }
    }

    It 'does not use the graceful path when it is not requested' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        $script:Calls | Should -Not -Contain 'graceful-stop'
        $script:Calls | Should -Contain 'stop:SPCache'
        ($state.Services | Where-Object Name -eq 'SPCache').GracefulAttempted | Should -BeFalse
    }

    It 'warns, logs an event and keeps going when one service cannot be stopped' {
        Mock Stop-Service { if ($Name -eq 'SPTraceV4') { throw 'access denied' }; $script:Svc[$Name].Status = 'Stopped'; [void]$script:Calls.Add("stop:$Name") }
        { Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder -WarningAction SilentlyContinue } | Should -Not -Throw

        $script:Calls | Should -Contain 'stop:SPAdminV4'
        $script:Calls | Should -Contain 'stop:SPCache'
        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Warning' -and $Message -like '*SPTraceV4*' }
    }

    It 'warns when iisreset fails to stop IIS (non-zero exit code) and keeps going' {
        Mock Start-Process { [void]$script:Calls.Add("process:$FilePath $ArgumentList"); [pscustomobject]@{ ExitCode = 1 } }
        { Stop-SPSUpdateServices -ShutdownProfile Basic -StateFolder $script:Folder -WarningAction SilentlyContinue } | Should -Not -Throw

        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Warning' -and $Message -like '*stop IIS*' }
    }

    It 'restores the services of an interrupted previous run before taking the new snapshot' {
        # A crashed run left SPTimerV4 disabled and stopped; its state file holds the real original state.
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        $leftover = Join-Path -Path $script:Folder -ChildPath "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_20260101000000000.json"
        [pscustomobject]@{ Computer = 'X'; IisReset = $false; Services = @([pscustomobject]@{ Name = 'SPTimerV4'; StartType = 'Automatic'; Status = 'Running'; GracefulAttempted = $false }) } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $leftover
        $script:Svc['SPTimerV4'].StartType = 'Disabled'
        $script:Svc['SPTimerV4'].Status = 'Stopped'

        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder -WarningAction SilentlyContinue

        Test-Path -Path $leftover | Should -BeFalse
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json
        ($state.Services | Where-Object Name -eq 'SPTimerV4').StartType | Should -Be 'Automatic'
        ($state.Services | Where-Object Name -eq 'SPTimerV4').Status | Should -Be 'Running'
    }

    It 'stops with an error, touches nothing and keeps the leftover file when the previous run cannot be restored' {
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        $leftover = Join-Path -Path $script:Folder -ChildPath "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_20260101000000000.json"
        [pscustomobject]@{ Computer = 'X'; IisReset = $false; Services = @([pscustomobject]@{ Name = 'SPTimerV4'; StartType = 'Automatic'; Status = 'Running'; GracefulAttempted = $false }) } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $leftover
        $script:Svc['SPTimerV4'].StartType = 'Disabled'
        $script:Svc['SPTimerV4'].Status = 'Stopped'
        Mock Start-Service { throw 'service cannot start' }

        { Stop-SPSUpdateServices -ShutdownProfile Basic -StateFolder $script:Folder -WarningAction SilentlyContinue } | Should -Throw '*could not be restored*'

        Test-Path -Path $leftover | Should -BeTrue
        @($script:Calls | Where-Object { $_ -like 'stop:*' }).Count | Should -Be 0
        @(Get-ChildItem -Path $script:Folder -Filter 'SPSUpdate-ServicesState_*.json').Count | Should -Be 1
        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Error' -and $Message -like '*could not be restored*' }
    }

    It 'records its own process as the owner of the state file' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder
        $state = Get-Content -Path $r.Path -Raw | ConvertFrom-Json

        $state.ProcessId | Should -Be $PID
        $state.ProcessStart | Should -Not -BeNullOrEmpty
    }

    It 'refuses to start, changes nothing and keeps the file when another update is running on this server' {
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        $running = Join-Path -Path $script:Folder -ChildPath "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_20260101000000000.json"
        [pscustomobject]@{ Computer = 'X'; ProcessId = ($PID + 1); ProcessStart = ([datetime]'2026-11-18T10:00:00').ToString('o'); IisReset = $false; Services = @([pscustomobject]@{ Name = 'SPTimerV4'; StartType = 'Automatic'; Status = 'Running'; GracefulAttempted = $false }) } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $running
        $script:Svc['SPTimerV4'].Status = 'Stopped'
        Mock Get-Process { [pscustomobject]@{ Id = $PID + 1; StartTime = [datetime]'2026-11-18T10:00:00' } }

        { Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder } | Should -Throw '*Another ProductUpdate is running*'

        Test-Path -Path $running | Should -BeTrue
        @($script:Calls).Count | Should -Be 0
        @(Get-ChildItem -Path $script:Folder -Filter 'SPSUpdate-ServicesState_*.json').Count | Should -Be 1
    }

    It 'treats a state file whose owner process is gone as a leftover and restores it' {
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        $gone = Join-Path -Path $script:Folder -ChildPath "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_20260101000000000.json"
        [pscustomobject]@{ Computer = 'X'; ProcessId = ($PID + 1); ProcessStart = ([datetime]'2026-11-18T10:00:00').ToString('o'); IisReset = $false; Services = @([pscustomobject]@{ Name = 'SPTimerV4'; StartType = 'Automatic'; Status = 'Running'; GracefulAttempted = $false }) } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $gone
        Mock Get-Process { $null }

        $null = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder -WarningAction SilentlyContinue

        Test-Path -Path $gone | Should -BeFalse
        $script:Calls | Should -Contain 'start:SPTimerV4'
    }

    It 'ignores the legacy ServicesStatus_*.json files' {
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        $legacy = Join-Path -Path $script:Folder -ChildPath "ServicesStatus_$($env:COMPUTERNAME)_20260101000000.json"
        '[{"Name":"SPTimerV4","StartType":"Disabled","Status":"Stopped"}]' | Set-Content -Path $legacy
        $null = Stop-SPSUpdateServices -ShutdownProfile Basic -StateFolder $script:Folder
        Test-Path -Path $legacy | Should -BeTrue
    }

    It 'honours -WhatIf: no service is touched and no state file is written' {
        $r = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder $script:Folder -WhatIf

        $r.Path | Should -BeNullOrEmpty
        @($script:Calls).Count | Should -Be 0
        Test-Path -Path $script:Folder | Should -BeFalse
    }

    It 'rejects an unknown profile' {
        { Stop-SPSUpdateServices -ShutdownProfile 'Turbo' -StateFolder $script:Folder } | Should -Throw
    }
}
