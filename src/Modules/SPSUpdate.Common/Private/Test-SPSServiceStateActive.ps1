function Test-SPSServiceStateActive {
    <#
        .SYNOPSIS
        Tells whether a service state file belongs to an update that is running right now.

        .DESCRIPTION
        Stop-SPSUpdateServices records the process that owns the state file (its id and its start time).
        A file is active when that process is another one than the caller, still runs, and is the same
        process (the start time rules out a process id that was reused after a crash or a reboot). An
        active file must not be restored or deleted, since its services are stopped on purpose. A file
        without owner, with an unreadable content, or whose owner is gone is a leftover of an
        interrupted update.

        .PARAMETER Path
        Path of the state file.

        .OUTPUTS
        $true when the owner of the file is another running process, otherwise $false.

        .EXAMPLE
        Test-SPSServiceStateActive -Path 'F:\SCRIPTS\SPSUpdate\Results\SPSUpdate-ServicesState_APP1_20261118153000123.json'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    try {
        $state = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $false
    }
    if ($state.PSObject.Properties.Name -notcontains 'ProcessId' -or $null -eq $state.ProcessId) {
        return $false
    }

    $ownerId = [int]$state.ProcessId
    if ($ownerId -eq $PID) {
        return $false
    }
    $owner = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
    if ($null -eq $owner) {
        return $false
    }
    if ([string]::IsNullOrEmpty("$($state.ProcessStart)")) {
        return $true
    }
    try {
        return ([System.Math]::Abs(($owner.StartTime - [datetime]$state.ProcessStart).TotalSeconds) -lt 5)
    }
    catch {
        return $true
    }
}
