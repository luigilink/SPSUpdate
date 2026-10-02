function Resolve-SPSWizardOutcome {
    <#
    .SYNOPSIS
        Maps a psconfig.exe exit code to a dashboard Wizard state in a consistent way.

    .DESCRIPTION
        Start-SPSConfigExe (local master) and Start-SPSConfigExeRemote (remote servers)
        both run the same psconfig.exe command chain
        ("-cmd upgrade -inplace b2b -wait -cmd applicationcontent -install -cmd
        installfeatures -cmd secureresources -cmd services -install") and return the
        process exit code. A non-zero exit code is reported by psconfig for the whole
        chain, so a later sub-command (installfeatures / secureresources / services) can
        return non-zero even though the build-to-build upgrade itself completed
        successfully. In that situation the authoritative per-server patch status is
        'NoActionRequired'.

        This helper centralises the decision so the local and remote wizard paths behave
        identically:
          - exit 0 (or no exit code) -> Done
          - non-zero exit but the server reports NoActionRequired -> Done (warning)
          - non-zero exit and the server still requires action -> Failed

    .PARAMETER ExitCode
        The psconfig.exe exit code returned by Start-SPSConfigExe /
        Start-SPSConfigExeRemote. Accepts an array (the last integer is used) or $null.

    .PARAMETER Server
        The server the wizard ran on, used both for the authoritative patch-status
        re-check and for human-readable detail messages.

    .PARAMETER PatchStatus
        Optional injected patch status. When omitted, the authoritative status is read
        with Get-SPSServersPatchStatus -Server <Server>. Mainly used for testing.

    .EXAMPLE
        Resolve-SPSWizardOutcome -ExitCode 0 -Server 'APP01'

    .EXAMPLE
        Resolve-SPSWizardOutcome -ExitCode -1 -Server 'APP01' -PatchStatus 'NoActionRequired'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [Object]
        $ExitCode,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [AllowNull()]
        [Object]
        $PatchStatus
    )

    $errorCodeLink = 'https://aka.ms/installerrorcodes'

    # Normalise the exit code: callers may pass an array of pipeline output, so keep the
    # last integer value (that is the psconfig.exe exit code).
    $exit = @($ExitCode) | Where-Object { $_ -is [int] } | Select-Object -Last 1

    if ($null -eq $exit -or [int]$exit -eq 0) {
        $detail = if ($null -ne $exit) { "PSConfig completed (exit $([int]$exit))" } else { 'PSConfig completed' }
        return [PSCustomObject]@{
            State    = 'Done'
            ExitCode = $exit
            Detail   = $detail
        }
    }

    # Non-zero exit code. Re-check the authoritative patch status before declaring a
    # failure: the upgrade session may have finished successfully while a later psconfig
    # sub-command returned non-zero.
    if ($PSBoundParameters.ContainsKey('PatchStatus')) {
        $status = $PatchStatus
    }
    else {
        $status = $null
        try {
            $status = Get-SPSServersPatchStatus -Server $Server
        }
        catch {
            Write-Warning -Message ("Unable to re-check patch status on '$Server' after PSConfig: " + `
                    "$($_.Exception.Message)")
        }
    }

    # Track whether we actually obtained a usable status: a failed or empty lookup must not
    # be reported as "action required" (which would imply a confirmed upgrade-status result).
    $statusKnown = -not [string]::IsNullOrWhiteSpace("$status")

    if ($statusKnown -and "$status" -eq 'NoActionRequired') {
        Write-Warning -Message ("PSConfig on '$Server' returned exit $([int]$exit) but the server reports " + `
                "NoActionRequired; treating the upgrade as completed. Error codes: $errorCodeLink")
        return [PSCustomObject]@{
            State    = 'Done'
            ExitCode = [int]$exit
            Detail   = "PSConfig returned exit $([int]$exit) but $Server reports NoActionRequired (upgrade completed). Error codes: $errorCodeLink"
        }
    }

    if ($statusKnown) {
        $failDetail = "PSConfig failed (exit $([int]$exit)); $Server still requires action (status: $status). Error codes: $errorCodeLink"
    }
    else {
        $failDetail = "PSConfig failed (exit $([int]$exit)) and the patch status for $Server could not be confirmed; treating as failed. Error codes: $errorCodeLink"
    }

    return [PSCustomObject]@{
        State    = 'Failed'
        ExitCode = [int]$exit
        Detail   = $failDetail
    }
}
