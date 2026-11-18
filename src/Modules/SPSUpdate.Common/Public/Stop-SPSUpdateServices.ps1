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
        state file BEFORE the first change (the file is written aside and then moved in place, so it is
        never half written). An interrupted run can be repaired with Restore-SPSUpdateServices. The
        Distributed Cache removal is recorded in the file BEFORE it is attempted.

        State files left behind by a previous interrupted run on this computer are restored first. When
        that fails the function stops with an error and keeps the files: taking a new snapshot of
        services that are still disabled would record the wrong original state. A state file whose
        owner process (recorded in the file) is still running belongs to an update in progress: the
        function refuses to start and changes nothing.

        A service that cannot be disabled or stopped raises a warning and an event log entry; the
        install then continues (it is slower, not unsafe).

        .PARAMETER ShutdownProfile
        Basic (default) or Extended.

        .PARAMETER GracefulStopDistributedCache
        Extended profile only: gracefully stop the Distributed Cache host before the install.
        Run it on one Distributed Cache server at a time.

        .PARAMETER StateFolder
        Folder that receives the state file (created if missing) and is searched for leftover files.

        .PARAMETER StatePath
        Path of the state file to write. By default a new name is built in StateFolder. A caller that must
        restore the services whatever happens passes its own path, so it knows the file before any change.

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
        $StateFolder,

        [Parameter()]
        [System.String]
        $StatePath
    )

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Stop the SharePoint services before the update (profile $ShutdownProfile)")) {
        return [PSCustomObject]@{ Path = $null; ShutdownProfile = $ShutdownProfile; Services = @() }
    }

    if (-not (Test-Path -Path $StateFolder)) {
        New-Item -Path $StateFolder -ItemType Directory -Force | Out-Null
    }

    # A state file whose owner still runs belongs to an update that is in progress on this server: its
    # services are stopped on purpose, so a second update must neither restore them nor stop them again.
    foreach ($candidate in @(Get-ChildItem -Path $StateFolder -Filter "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_*.json" -File -ErrorAction SilentlyContinue)) {
        if (Test-SPSServiceStateActive -Path $candidate.FullName) {
            $busyMessage = "Another ProductUpdate is running on this server (state file $($candidate.FullName)). Wait for it to finish; nothing was changed."
            Add-SPSUpdateEvent -Message $busyMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Error'
            throw $busyMessage
        }
    }

    # Repair a previous interrupted run first: its state file holds the real original state. A new
    # snapshot of services that are still disabled would record the wrong state, so stop here instead.
    if (-not (Restore-SPSUpdateServices -StateFolder $StateFolder)) {
        $abortMessage = "The services of an interrupted ProductUpdate could not be restored (state files in $StateFolder). Fix the problem and run Restore-SPSUpdateServices -StateFolder '$StateFolder' before the next update."
        Add-SPSUpdateEvent -Message $abortMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Error'
        throw $abortMessage
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
                Name              = $name
                StartType         = "$($service.StartType)"
                Status            = "$($service.Status)"
                GracefulAttempted = $false
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

    if ([string]::IsNullOrEmpty($StatePath)) {
        $StatePath = Get-SPSServiceStatePath -StateFolder $StateFolder
    }
    $ownerStart = ''
    try { $ownerStart = (Get-Process -Id $PID -ErrorAction Stop).StartTime.ToString('o') } catch { $ownerStart = '' }
    $writeState = {
        $stateObject = [PSCustomObject]@{
            Computer        = "$($env:COMPUTERNAME)"
            ProcessId       = $PID
            ProcessStart    = $ownerStart
            Created         = (Get-Date).ToString('s')
            ShutdownProfile = $ShutdownProfile
            IisReset        = $isBasic
            Services        = $restoreList.ToArray()
        }
        # Written aside then moved in place: an interruption never leaves a half written state file.
        $temporaryPath = "$StatePath.tmp"
        ConvertTo-Json -InputObject $stateObject -Depth 4 | Set-Content -Path $temporaryPath -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $temporaryPath -Destination $StatePath -Force -ErrorAction Stop
    }
    & $writeState
    Write-Verbose -Message "Services status saved to $StatePath"

    $stopped = New-Object -TypeName 'System.Collections.Generic.List[System.String]'
    foreach ($target in $targets) {
        $name = $target.Name

        if ($name -eq 'SPCache' -and $GracefulStopDistributedCache) {
            try {
                if ($null -eq (Get-Command -Name 'Stop-AFCacheHost' -ErrorAction SilentlyContinue)) {
                    Import-Module -Name (Join-Path -Path $env:CommonProgramFiles -ChildPath 'microsoft shared\Web Server Extensions\16\BIN\CacheModules\DistributedCacheAdministration\DistributedCacheAdministration') -ErrorAction Stop
                }
                Use-SPCacheCluster
                # Record the intention BEFORE the destructive calls: the restore finds out what happened.
                $target.GracefulAttempted = $true
                & $writeState
                Write-Verbose -Message 'Gracefully stopping the Distributed Cache host.'
                Stop-AFCacheHost -Graceful -ComputerName $env:COMPUTERNAME -CachePort 22233 -ErrorAction Stop
                Remove-SPDistributedCacheServiceInstance -ErrorAction Stop
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
        try {
            $iis = Start-Process -FilePath 'iisreset.exe' -ArgumentList '-stop -noforce' -Wait -PassThru -ErrorAction Stop
            if ($null -ne $iis -and $iis.ExitCode -ne 0) {
                throw "iisreset -stop exited with code $($iis.ExitCode)"
            }
        }
        catch {
            $iisMessage = "Could not stop IIS before the update: $($_.Exception.Message). The installation continues but may take longer."
            Write-Warning -Message $iisMessage
            Add-SPSUpdateEvent -Message $iisMessage -Source 'Stop-SPSUpdateServices' -EntryType 'Warning'
        }
    }

    Add-SPSUpdateEvent -Message "Services stopped before the update (profile $ShutdownProfile): $($stopped -join ', ')" -Source 'Stop-SPSUpdateServices' -EntryType 'Information'
    Write-Verbose -Message 'All services stopped. Starting installation process.'
    return [PSCustomObject]@{ Path = $StatePath; ShutdownProfile = $ShutdownProfile; Services = $stopped.ToArray() }
}
