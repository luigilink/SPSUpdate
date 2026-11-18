# Tests for Restore-SPSUpdateServices (state restore, partial failure, Distributed Cache reconcile, IIS, folder mode).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:StopPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Stop-SPSUpdateServices.ps1'
    $script:RestorePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Restore-SPSUpdateServices.ps1'
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Private/Get-SPSServiceStatePath.ps1')
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

    function New-StateFile {
        param([object[]] $Services, [bool] $IisReset = $false, [switch] $Legacy, [string] $Folder = $script:TmpDir, [string] $Name = ('state-' + [guid]::NewGuid() + '.json'))
        $path = Join-Path -Path $Folder -ChildPath $Name
        if ($Legacy) { ConvertTo-Json -InputObject @($Services) -Depth 4 | Set-Content -Path $path }
        else { ConvertTo-Json -InputObject ([pscustomobject]@{ Computer = 'X'; IisReset = $IisReset; Services = @($Services) }) -Depth 4 | Set-Content -Path $path }
        return $path
    }
    function New-ServiceEntry { param($Name, $StartType = 'Automatic', $Status = 'Running', [bool] $GracefulAttempted = $false) [pscustomobject]@{ Name = $Name; StartType = $StartType; Status = $Status; GracefulAttempted = $GracefulAttempted } }
}

AfterAll {
    if ($script:TmpDir -and (Test-Path $script:TmpDir)) { Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Restore-SPSUpdateServices (one state file)' {
    BeforeEach {
        $script:Calls = New-Object System.Collections.ArrayList
        $script:DCacheInstancePresent = $true
        Mock Set-Service { [void]$script:Calls.Add("set:${Name}:$StartupType") }
        Mock Start-Service { [void]$script:Calls.Add("start:$Name") }
        Mock Start-Process { [void]$script:Calls.Add("process:$FilePath $ArgumentList"); [pscustomobject]@{ ExitCode = 0 } }
        Mock Add-SPSUpdateEvent { }
        Mock Add-SPDistributedCacheServiceInstance { [void]$script:Calls.Add('add-dcache') }
        Mock Get-SPServiceInstance { if ($script:DCacheInstancePresent) { [pscustomobject]@{ TypeName = 'Distributed Cache' } } }
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

    It 'adds the Distributed Cache instance back when it was removed after the intention was recorded' {
        $script:DCacheInstancePresent = $false
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache' 'Automatic' 'Running' $true))
        $null = Restore-SPSUpdateServices -Path $p

        $script:Calls | Should -Contain 'add-dcache'
        $script:Calls | Should -Not -Contain 'start:SPCache'
    }

    It 'restores SPCache like any service when the instance is still there (the removal never happened)' {
        $script:DCacheInstancePresent = $true
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache' 'Automatic' 'Running' $true))
        $ok = Restore-SPSUpdateServices -Path $p

        $ok | Should -BeTrue
        $script:Calls | Should -Not -Contain 'add-dcache'
        $script:Calls | Should -Contain 'set:SPCache:Automatic'
        $script:Calls | Should -Contain 'start:SPCache'
    }

    It 'assumes the instance was removed when it cannot be read' {
        Mock Get-SPServiceInstance { throw 'farm not reachable' }
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache' 'Automatic' 'Running' $true))
        $null = Restore-SPSUpdateServices -Path $p

        $script:Calls | Should -Contain 'add-dcache'
    }

    It 'keeps the file and returns false when the Distributed Cache instance cannot be added back' {
        $script:DCacheInstancePresent = $false
        Mock Add-SPDistributedCacheServiceInstance { throw 'cache cluster error' }
        $p = New-StateFile -Services @((New-ServiceEntry 'SPCache' 'Automatic' 'Running' $true))
        $ok = Restore-SPSUpdateServices -Path $p -WarningAction SilentlyContinue

        $ok | Should -BeFalse
        Test-Path -Path $p | Should -BeTrue
    }

    It 'starts IIS again when the Basic profile stopped it' {
        $p = New-StateFile -Services @((New-ServiceEntry 'IISADMIN')) -IisReset $true
        $ok = Restore-SPSUpdateServices -Path $p

        $ok | Should -BeTrue
        $script:Calls | Should -Contain 'process:iisreset.exe -start'
    }

    It 'keeps the file, logs an error and returns false when iisreset -start exits with a failure code' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        $p = New-StateFile -Services @((New-ServiceEntry 'IISADMIN')) -IisReset $true
        $ok = Restore-SPSUpdateServices -Path $p -WarningAction SilentlyContinue

        $ok | Should -BeFalse
        Test-Path -Path $p | Should -BeTrue
        Should -Invoke Add-SPSUpdateEvent -ParameterFilter { $EntryType -eq 'Error' -and $Message -like '*IIS*' }
    }

    It 'keeps the file and returns false when iisreset cannot be launched' {
        Mock Start-Process { throw 'file not found' }
        $p = New-StateFile -Services @((New-ServiceEntry 'IISADMIN')) -IisReset $true
        $ok = Restore-SPSUpdateServices -Path $p -WarningAction SilentlyContinue

        $ok | Should -BeFalse
        Test-Path -Path $p | Should -BeTrue
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

    It 'honours -WhatIf: nothing is restored and the file is kept' {
        $p = New-StateFile -Services @((New-ServiceEntry 'SPTimerV4'))
        $null = Restore-SPSUpdateServices -Path $p -WhatIf

        @($script:Calls).Count | Should -Be 0
        Test-Path -Path $p | Should -BeTrue
    }
}

Describe 'Restore-SPSUpdateServices (state folder)' {
    BeforeEach {
        $script:Calls = New-Object System.Collections.ArrayList
        $script:Folder = Join-Path -Path $script:TmpDir -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        Mock Set-Service { [void]$script:Calls.Add("set:${Name}:$StartupType") }
        Mock Start-Service { [void]$script:Calls.Add("start:$Name") }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Add-SPSUpdateEvent { }
        Mock Get-SPServiceInstance { [pscustomobject]@{ TypeName = 'Distributed Cache' } }
    }

    It 'returns true when the folder does not exist or holds no state file' {
        Restore-SPSUpdateServices -StateFolder (Join-Path $script:TmpDir 'nothing-here') | Should -BeTrue
        Restore-SPSUpdateServices -StateFolder $script:Folder | Should -BeTrue
    }

    It 'restores every state file of this computer, oldest first, and ignores the other files' {
        $c = $env:COMPUTERNAME
        $null = New-StateFile -Folder $script:Folder -Name "SPSUpdate-ServicesState_${c}_20260102000000000.json" -Services @((New-ServiceEntry 'SPTimerV4'))
        $null = New-StateFile -Folder $script:Folder -Name "SPSUpdate-ServicesState_${c}_20260101000000000.json" -Services @((New-ServiceEntry 'SPAdminV4'))
        $other = New-StateFile -Folder $script:Folder -Name 'SPSUpdate-ServicesState_OTHERPC_20260101000000000.json' -Services @((New-ServiceEntry 'W3SVC'))

        $ok = Restore-SPSUpdateServices -StateFolder $script:Folder -WarningAction SilentlyContinue

        $ok | Should -BeTrue
        @($script:Calls | Where-Object { $_ -like 'start:*' }) | Should -Be @('start:SPAdminV4', 'start:SPTimerV4')
        Test-Path -Path $other | Should -BeTrue
    }

    It 'returns false when one file fails, and still restores the others' {
        $c = $env:COMPUTERNAME
        $bad = New-StateFile -Folder $script:Folder -Name "SPSUpdate-ServicesState_${c}_20260101000000000.json" -Services @((New-ServiceEntry 'SPAdminV4'))
        $null = New-StateFile -Folder $script:Folder -Name "SPSUpdate-ServicesState_${c}_20260102000000000.json" -Services @((New-ServiceEntry 'SPTimerV4'))
        Mock Start-Service { if ($Name -eq 'SPAdminV4') { throw 'boom' }; [void]$script:Calls.Add("start:$Name") }

        $ok = Restore-SPSUpdateServices -StateFolder $script:Folder -WarningAction SilentlyContinue

        $ok | Should -BeFalse
        $script:Calls | Should -Contain 'start:SPTimerV4'
        Test-Path -Path $bad | Should -BeTrue
    }

    It 'honours -WhatIf on the folder' {
        $c = $env:COMPUTERNAME
        $f = New-StateFile -Folder $script:Folder -Name "SPSUpdate-ServicesState_${c}_20260101000000000.json" -Services @((New-ServiceEntry 'SPAdminV4'))

        $null = Restore-SPSUpdateServices -StateFolder $script:Folder -WhatIf

        @($script:Calls).Count | Should -Be 0
        Test-Path -Path $f | Should -BeTrue
    }
}
