# Tests for Restore-SPSUpdateServices (state restore, partial failure, graceful Distributed Cache, legacy file).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:StopPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Stop-SPSUpdateServices.ps1'
    $script:RestorePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Restore-SPSUpdateServices.ps1'
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

    $script:TmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsupd-svc-' + [guid]::NewGuid())
    New-Item -Path $script:TmpDir -ItemType Directory -Force | Out-Null

    function New-StateFile {
        param([object[]] $Services, [bool] $IisReset = $false, [switch] $Legacy)
        $path = Join-Path -Path $script:TmpDir -ChildPath ('state-' + [guid]::NewGuid() + '.json')
        if ($Legacy) { ConvertTo-Json -InputObject @($Services) -Depth 4 | Set-Content -Path $path }
        else { ConvertTo-Json -InputObject ([pscustomobject]@{ Computer = 'X'; IisReset = $IisReset; Services = @($Services) }) -Depth 4 | Set-Content -Path $path }
        return $path
    }
    function New-ServiceEntry { param($Name, $StartType = 'Automatic', $Status = 'Running', [bool] $Graceful = $false) [pscustomobject]@{ Name = $Name; StartType = $StartType; Status = $Status; Graceful = $Graceful } }
}

AfterAll {
    if ($script:TmpDir -and (Test-Path $script:TmpDir)) { Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Restore-SPSUpdateServices' {
    BeforeEach {
        $script:Calls = New-Object System.Collections.ArrayList
        Mock Set-Service { [void]$script:Calls.Add("set:${Name}:$StartupType") }
        Mock Start-Service { [void]$script:Calls.Add("start:$Name") }
        Mock Start-Process { [void]$script:Calls.Add("process:$FilePath $ArgumentList") }
        Mock Add-SPSUpdateEvent { }
        Mock Add-SPDistributedCacheServiceInstance { [void]$script:Calls.Add('add-dcache') }
    }

    It 'puts back the startup type and starts the services that were running, in file order' {
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache'), (New-ServiceEntry 'OSearch16' 'Manual' 'Running'), (New-ServiceEntry 'SPTimerV4'))
        $ok = Restore-SPSUpdateServices -Path $p

        $ok | Should -BeTrue
        @($script:Calls) | Should -Be @('set:SPCache:Automatic', 'start:SPCache', 'set:OSearch16:Manual', 'start:OSearch16', 'set:SPTimerV4:Automatic', 'start:SPTimerV4')
    }

    It 'keeps a service stopped when it was not running before' {
        $p = New-StateFile -Services @((New-ServiceEntry 'OSearch16' 'Manual' 'Stopped'))
        $null = Restore-SPSUpdateServices -Path $p

        $script:Calls | Should -Contain 'set:OSearch16:Manual'
        $script:Calls | Should -Not -Contain 'start:OSearch16'
    }

    It 'deletes the state file once everything is restored' {
        $p = New-StateFile -Services @((New-ServiceEntry 'SPTimerV4'))
        $null = Restore-SPSUpdateServices -Path $p
        Test-Path -Path $p | Should -BeFalse
    }

    It 'restores the other services, keeps the file, logs an error and returns false when one fails' {
        Mock Start-Service { if ($Name -eq 'SPAdminV4') { throw 'timeout' }; [void]$script:Calls.Add("start:$Name") }
        $p = New-StateFile -Services @((New-ServiceEntry 'SPAdminV4'), (New-ServiceEntry 'SPTimerV4'))
        $ok = Restore-SPSUpdateServices -Path $p -WarningAction SilentlyContinue

        $ok | Should -BeFalse
        $script:Calls | Should -Contain 'start:SPTimerV4'
        Test-Path -Path $p | Should -BeTrue
        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Error' -and $Message -like '*SPAdminV4*' }
    }

    It 'adds the Distributed Cache instance back instead of starting SPCache after a graceful stop' {
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache' 'Automatic' 'Running' $true))
        $null = Restore-SPSUpdateServices -Path $p

        $script:Calls | Should -Contain 'add-dcache'
        $script:Calls | Should -Not -Contain 'start:SPCache'
    }

    It 'starts IIS again when the Basic profile stopped it' {
        $p = New-StateFile -Services @((New-ServiceEntry 'IISADMIN')) -IisReset $true
        $null = Restore-SPSUpdateServices -Path $p
        $script:Calls | Should -Contain 'process:iisreset.exe -start'
    }

    It 'does not run iisreset when it was not used' {
        $p = New-StateFile -Services @((New-ServiceEntry 'W3SVC'))
        $null = Restore-SPSUpdateServices -Path $p
        @($script:Calls | Where-Object { $_ -like 'process:*' }).Count | Should -Be 0
    }

    It 'accepts the legacy array format written by earlier versions' {
        $p = New-StateFile -Services @((New-ServiceEntry 'SPTimerV4' 'Automatic' 'Running')) -Legacy
        $ok = Restore-SPSUpdateServices -Path $p

        $ok | Should -BeTrue
        $script:Calls | Should -Contain 'start:SPTimerV4'
    }

    It 'throws when the state file does not exist' {
        { Restore-SPSUpdateServices -Path (Join-Path $script:TmpDir 'missing.json') } | Should -Throw '*not found*'
    }
}
