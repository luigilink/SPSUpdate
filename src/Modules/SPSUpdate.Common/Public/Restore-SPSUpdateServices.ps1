function Restore-SPSUpdateServices {
    <#
        .SYNOPSIS
        Restores the services saved by Stop-SPSUpdateServices.

        .DESCRIPTION
        Reads a service state file and, in the stored order, puts back each service's startup type and
        starts the ones that were running before the update. IIS is started again when the Basic profile
        stopped it with iisreset (its exit code is checked).

        A Distributed Cache host for which a graceful stop was attempted is reconciled: when its service
        instance was removed from the farm, it is added back with Add-SPDistributedCacheServiceInstance;
        when the instance is still there, the SPCache service is restored like any other service.

        Every failure raises a warning and an event log entry, and the remaining services are still
        restored. A state file is deleted only when everything was restored, so a failed restore can be
        retried.

        With -StateFolder, every state file of this computer in the folder is restored, oldest first. This
        repairs a server after an interrupted update, and ProductUpdate does it before anything else:

        Restore-SPSUpdateServices -StateFolder 'F:\SCRIPTS\SPSUpdate\Results'

        .PARAMETER Path
        Path of one state file.

        .PARAMETER StateFolder
        Folder that holds the state files of Stop-SPSUpdateServices.

        .OUTPUTS
        $true when every service was restored (or there was nothing to restore), otherwise $false.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Path')]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Folder')]
        [System.String]
        $StateFolder
    )

    if ($PSCmdlet.ParameterSetName -eq 'Folder') {
        if (-not (Test-Path -Path $StateFolder)) {
            return $true
        }
        if (-not $PSCmdlet.ShouldProcess($StateFolder, 'Restore the services of an interrupted update')) {
            return $true
        }
        $stateFiles = @(Get-ChildItem -Path $StateFolder -Filter "SPSUpdate-ServicesState_$($env:COMPUTERNAME)_*.json" -File -ErrorAction SilentlyContinue | Sort-Object -Property Name)
        $allRestored = $true
        foreach ($stateFile in $stateFiles) {
            $foundMessage = "A service state file from an interrupted ProductUpdate was found ($($stateFile.FullName)). Restoring the services."
            Write-Warning -Message $foundMessage
            Add-SPSUpdateEvent -Message $foundMessage -Source 'Restore-SPSUpdateServices' -EntryType 'Warning'
            if (-not (Restore-SPSUpdateServices -Path $stateFile.FullName)) {
                $allRestored = $false
            }
        }
        return $allRestored
    }

    if (-not (Test-Path -Path $Path)) {
        throw "Service state file not found: $Path"
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Restore the services saved before the update')) {
        return $true
    }

    $state = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $services = if ($state.PSObject.Properties.Name -contains 'Services') { @($state.Services) } else { @($state) }
    $iisReset = ($state.PSObject.Properties.Name -contains 'IisReset') -and [bool]$state.IisReset

    $failures = 0
    foreach ($service in $services) {
        if ($null -eq $service -or [string]::IsNullOrEmpty("$($service.Name)")) { continue }
        Write-Verbose -Message "Service: $($service.Name) - Startup type before installation: $($service.StartType) - Status before installation: $($service.Status)"
        $instanceAddedBack = $false

        if ($service.PSObject.Properties.Name -contains 'GracefulAttempted' -and [bool]$service.GracefulAttempted) {
            # The removal of the instance was decided before it was done: find out whether it happened.
            $instanceMissing = $true
            try {
                $existing = @(Get-SPServiceInstance -Server $env:COMPUTERNAME -ErrorAction Stop | Where-Object { $_.TypeName -eq 'Distributed Cache' })
                if ($existing.Count -gt 0) { $instanceMissing = $false }
            }
            catch {
                Write-Verbose -Message "Could not read the Distributed Cache service instance: $($_.Exception.Message). Assuming it was removed."
            }
            if ($instanceMissing) {
                try {
                    Write-Verbose -Message 'Adding the Distributed Cache service instance back.'
                    Add-SPDistributedCacheServiceInstance -ErrorAction Stop
                    $instanceAddedBack = $true
                }
                catch {
                    $failures++
                    $message = "Could not add the Distributed Cache service instance back after the update: $($_.Exception.Message)"
                    Write-Warning -Message $message
                    Add-SPSUpdateEvent -Message $message -Source 'Restore-SPSUpdateServices' -EntryType 'Error'
                    continue
                }
            }
            else {
                Write-Verbose -Message 'The Distributed Cache service instance is still in the farm: restoring the SPCache service like the others.'
            }
        }

        try {
            Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction Stop
        }
        catch {
            $failures++
            $message = "Could not restore the startup type '$($service.StartType)' of service $($service.Name): $($_.Exception.Message)"
            Write-Warning -Message $message
            Add-SPSUpdateEvent -Message $message -Source 'Restore-SPSUpdateServices' -EntryType 'Error'
        }

        if ($instanceAddedBack) {
            # Adding the instance provisions and starts the service: only its startup type had to be put back.
            continue
        }

        if ("$($service.Status)" -eq 'Running') {
            try {
                Start-Service -Name $service.Name -ErrorAction Stop
            }
            catch {
                $failures++
                $message = "Could not start service $($service.Name) after the update: $($_.Exception.Message)"
                Write-Warning -Message $message
                Add-SPSUpdateEvent -Message $message -Source 'Restore-SPSUpdateServices' -EntryType 'Error'
            }
        }
        else {
            Write-Verbose -Message "Service: $($service.Name) was not running before installation. Keeping it stopped."
        }
    }

    if ($iisReset) {
        try {
            $iis = Start-Process -FilePath 'iisreset.exe' -ArgumentList '-start' -Wait -PassThru -ErrorAction Stop
            if ($null -ne $iis -and $iis.ExitCode -ne 0) {
                throw "iisreset -start exited with code $($iis.ExitCode)"
            }
        }
        catch {
            $failures++
            $message = "Could not start IIS again after the update: $($_.Exception.Message)"
            Write-Warning -Message $message
            Add-SPSUpdateEvent -Message $message -Source 'Restore-SPSUpdateServices' -EntryType 'Error'
        }
    }

    if ($failures -eq 0) {
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        Write-Verbose -Message 'All services restored.'
        return $true
    }

    Write-Warning -Message "$failures service operation(s) failed. The state file was kept so the restore can be retried: $Path"
    return $false
}
