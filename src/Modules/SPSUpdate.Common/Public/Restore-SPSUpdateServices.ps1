function Restore-SPSUpdateServices {
    <#
        .SYNOPSIS
        Restores the services saved by Stop-SPSUpdateServices.

        .DESCRIPTION
        Reads a service state file and, in the stored order, puts back each service's startup type and
        starts the ones that were running before the update. A Distributed Cache host that was stopped
        gracefully is added back with Add-SPDistributedCacheServiceInstance. IIS is started again when
        the Basic profile stopped it with iisreset.

        Every failure raises a warning and an event log entry, and the remaining services are still
        restored. The state file is deleted only when everything was restored, so a failed restore can
        be retried. Use it by hand to repair a server after an interrupted update:

        Restore-SPSUpdateServices -Path 'F:\SCRIPTS\SPSUpdate\Results\SPSUpdate-ServicesState_APP1_<date>.json'

        .PARAMETER Path
        Path of the state file.

        .OUTPUTS
        $true when every service was restored, otherwise $false.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Service state file not found: $Path"
    }

    $state = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $services = if ($state.PSObject.Properties.Name -contains 'Services') { @($state.Services) } else { @($state) }
    $iisReset = ($state.PSObject.Properties.Name -contains 'IisReset') -and [bool]$state.IisReset

    $failures = 0
    foreach ($service in $services) {
        if ($null -eq $service -or [string]::IsNullOrEmpty("$($service.Name)")) { continue }
        Write-Verbose -Message "Service: $($service.Name) - Startup type before installation: $($service.StartType) - Status before installation: $($service.Status)"

        if ($service.PSObject.Properties.Name -contains 'Graceful' -and [bool]$service.Graceful) {
            try {
                Write-Verbose -Message 'Adding the Distributed Cache service instance back.'
                Add-SPDistributedCacheServiceInstance -ErrorAction Stop
            }
            catch {
                $failures++
                $message = "Could not add the Distributed Cache service instance back after the update: $($_.Exception.Message)"
                Write-Warning -Message $message
                Add-SPSUpdateEvent -Message $message -Source 'Restore-SPSUpdateServices' -EntryType 'Error'
            }
            continue
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
        $null = Start-Process -FilePath 'iisreset.exe' -ArgumentList '-start' -Wait -PassThru
    }

    if ($failures -eq 0) {
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        Write-Verbose -Message 'All services restored.'
        return $true
    }

    Write-Warning -Message "$failures service operation(s) failed. The state file was kept so the restore can be retried: $Path"
    return $false
}
