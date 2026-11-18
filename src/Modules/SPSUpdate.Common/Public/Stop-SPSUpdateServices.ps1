function Stop-SPSUpdateServices {
    <#
        .SYNOPSIS
        Stops the SharePoint and IIS services before a cumulative update install, after saving their state.

        .DESCRIPTION
        Stopping the services before the installer runs avoids the extended install time seen on
        SharePoint Server Subscription Edition (files in use in the GAC). Two profiles are supported:

        - Basic: the historical behaviour. SPSearchHostController, SPTimerV4, IISADMIN and OSearch16 are
          disabled and stopped, then IIS is stopped with iisreset.
        - Extended: ordered stop of SPTimerV4, SPTraceV4, SPAdminV4, W3SVC, OSearch16,
          SPSearchHostController and SPCache, following the guidance published by Stefan Gossner.
          Only the services that exist on this server AND are running are touched, so the list follows
          the role of the server (a front-end without search or Distributed Cache is left alone).
          With -GracefulStopDistributedCache the Distributed Cache host is stopped gracefully
          (zero downtime patching) and falls back to a normal stop of SPCache if that fails.

        The original startup type and status of every service that is acted on is written to a JSON
        state file BEFORE the first change, so an interrupted run can be repaired with
        Restore-SPSUpdateServices. A state file left behind by a previous interrupted run on this
        computer is restored first, so the snapshot always describes the real original state.

        A service that cannot be disabled or stopped raises a warning and an event log entry; the
        install then continues (it is slower, not unsafe).

        .PARAMETER ShutdownProfile
        Basic (default) or Extended.

        .PARAMETER GracefulStopDistributedCache
        Extended profile only: gracefully stop the Distributed Cache host before the install.
        Run it on one Distributed Cache server at a time.

        .PARAMETER StateFolder
        Folder that receives the state file (created if missing).

        .EXAMPLE
        $state = Stop-SPSUpdateServices -ShutdownProfile Extended -StateFolder 'F:\SCRIPTS\SPSUpdate\Results'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateSet('Basic', 'Extended')]
        [System.String]
        $ShutdownProfile = 'Basic',

        [Parameter()]
        [System.Boolean]
        $GracefulStopDistributedCache = $false,

        [Parameter(Mandatory = $true)]
        [System.String]
        $StateFolder
    )

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Stop the SharePoint services before the update (profile $ShutdownProfile)")) {
        return [PSCustomObject]@{ Path = $null; ShutdownProfile = $ShutdownProfile; Services = @() }
    }

    if (-not (Test-Path -Path $StateFolder)) {
        New-Item -Path $StateFolder -ItemType Directory -Force | Out-Null
    }

    # Repair a previous interrupted run first: its state file holds the real original state.
    $leftovers = @(Get-ChildItem -Path $StateFolder -Filter "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_*.json" -File -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    foreach ($leftover in $leftovers) {
        $leftoverMessage = "A service state file from an interrupted ProductUpdate was found ($($leftover.FullName)). Restoring the services before continuing."
        Write-Warning -Message $leftoverMessage
        Add-SPSUpdateEvent -Message $leftoverMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Warning'
        $null = Restore-SPSUpdateServices -Path $leftover.FullName
    }

    if ($ShutdownProfile -eq 'Extended') {
        $stopOrder = @('SPTimerV4', 'SPTraceV4', 'SPAdminV4', 'W3SVC', 'OSearch16', 'SPSearchHostController', 'SPCache')
    }
    else {
        $stopOrder = @('SPSearchHostController', 'SPTimerV4', 'IISADMIN', 'OSearch16')
    }

    # Snapshot: Basic acts on every service present; Extended only on the ones that are running.
    $targets = New-Object -TypeName 'System.Collections.Generic.List[System.Object]'
    foreach ($name in $stopOrder) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-Verbose -Message "Service $name is not installed on this server. Skipping it."
            continue
        }
        if ($ShutdownProfile -eq 'Extended' -and "$($service.Status)" -ne 'Running') {
            Write-Verbose -Message "Service $name is not running ($($service.Status)). Leaving it untouched."
            continue
        }
        $targets.Add([PSCustomObject]@{
                Name      = $name
                StartType = "$($service.StartType)"
                Status    = "$($service.Status)"
                Graceful  = $false
            })
    }

    $isBasic = ($ShutdownProfile -eq 'Basic')
    if ($targets.Count -eq 0 -and -not $isBasic) {
        Write-Verbose -Message 'No SharePoint service to stop on this server.'
        return [PSCustomObject]@{ Path = $null; ShutdownProfile = $ShutdownProfile; Services = @() }
    }

    # Services are restored in the order stored in the file: as listed for Basic, reversed for Extended.
    $restoreList = New-Object -TypeName 'System.Collections.Generic.List[System.Object]'
    foreach ($target in $targets) {
        if ($isBasic) { $restoreList.Add($target) } else { $restoreList.Insert(0, $target) }
    }

    $statePath = Join-Path -Path $StateFolder -ChildPath ("SPSUpdate-ServicesState_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMddHHmmssfff').json")
    $writeState = {
        $stateObject = [PSCustomObject]@{
            Computer        = "$($env:COMPUTERNAME)"
            Created         = (Get-Date).ToString('s')
            ShutdownProfile = $ShutdownProfile
            IisReset        = $isBasic
            Services        = $restoreList.ToArray()
        }
        ConvertTo-Json -InputObject $stateObject -Depth 4 | Set-Content -Path $statePath -Encoding UTF8 -ErrorAction Stop
    }
    & $writeState
    Write-Verbose -Message "Services status saved to $statePath"

    $stopped = New-Object -TypeName 'System.Collections.Generic.List[System.String]'
    foreach ($target in $targets) {
        $name = $target.Name

        if ($name -eq 'SPCache' -and $GracefulStopDistributedCache) {
            try {
                if ($null -eq (Get-Command -Name 'Stop-AFCacheHost' -ErrorAction SilentlyContinue)) {
                    Import-Module -Name (Join-Path -Path $env:CommonProgramFiles -ChildPath 'microsoft shared\Web Server Extensions\16\BIN\CacheModules\DistributedCacheAdministration\DistributedCacheAdministration') -ErrorAction Stop
                }
                Use-SPCacheCluster
                Write-Verbose -Message 'Gracefully stopping the Distributed Cache host.'
                Stop-AFCacheHost -Graceful -ComputerName $env:COMPUTERNAME -CachePort 22233 -ErrorAction Stop
                Remove-SPDistributedCacheServiceInstance -ErrorAction Stop
                $target.Graceful = $true
                & $writeState
                $stopped.Add($name)
                continue
            }
            catch {
                $gracefulMessage = "Graceful stop of the Distributed Cache host failed: $($_.Exception.Message). Falling back to a normal stop of the SPCache service."
                Write-Warning -Message $gracefulMessage
                Add-SPSUpdateEvent -Message $gracefulMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Warning'
            }
        }

        try {
            Write-Verbose -Message "Stopping service: $name - Setting startup type to disabled"
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name $name -Force -ErrorAction Stop
            $stopped.Add($name)
        }
        catch {
            $failMessage = "Could not stop service $name before the update: $($_.Exception.Message). The installation continues but may take longer."
            Write-Warning -Message $failMessage
            Add-SPSUpdateEvent -Message $failMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Warning'
        }
    }

    if ($isBasic) {
        $null = Start-Process -FilePath 'iisreset.exe' -ArgumentList '-stop -noforce' -Wait -PassThru
    }

    Add-SPSUpdateEvent -Message "Services stopped before the update (profile $ShutdownProfile): $($stopped -join ', ')" -Source 'Stop-SPSUpdateServices' -EntryType 'Information'
    Write-Verbose -Message 'All services stopped. Starting installation process.'
    return [PSCustomObject]@{ Path = $statePath; ShutdownProfile = $ShutdownProfile; Services = $stopped.ToArray() }
}
