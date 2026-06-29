function Add-SPSUpdateEvent {
    <#
        .SYNOPSIS
        Writes an entry to the dedicated SPSUpdate Windows Event Log.

        .DESCRIPTION
        Add-SPSUpdateEvent writes an entry to the custom 'SPSUpdate' Windows Event
        Log under the specified Source. The Source typically identifies the stage
        that raised the event (e.g. 'Start-SPSProductUpdate', 'Mount-SPSContentDatabase'),
        which makes filtering and SCOM monitoring straightforward.

        When the Source does not exist yet, it is created under the SPSUpdate log;
        when the log itself does not exist, it is created on first use. A source
        previously mapped to another log (e.g. 'Application') is re-pointed to the
        SPSUpdate log. Creating an event source requires administrative privileges,
        which the SPSUpdate script already validates.

        Each message is prefixed with a header containing the module version, the
        current user and the computer name to ease cross-server correlation.

        .PARAMETER Message
        The event message body. The header is prepended automatically.

        .PARAMETER Source
        Identifier of the event source.

        .PARAMETER EntryType
        Severity of the event. Defaults to Information.

        .PARAMETER EventID
        Numeric event identifier. Defaults to 1.

        .EXAMPLE
        Add-SPSUpdateEvent -Message 'ProductUpdate completed' -Source 'Start-SPSProductUpdate' -EventID 1000
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Source,

        [Parameter()]
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [System.String]
        $EntryType = 'Information',

        [Parameter()]
        [System.UInt32]
        $EventID = 1
    )

    $LogName = 'SPSUpdate'

    # Ensure the event source exists and is mapped to the SPSUpdate log. A source
    # registered under another log (e.g. 'Application') is re-pointed to SPSUpdate
    # instead of silently giving up. Requires admin (the script validates it).
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($Source)) {
            $sourceLogName = [System.Diagnostics.EventLog]::LogNameFromSourceName($Source, '.')
            if ($LogName -ne $sourceLogName) {
                Write-Verbose -Message "Source '$Source' is mapped to log '$sourceLogName'; re-pointing it to '$LogName'."
                [System.Diagnostics.EventLog]::DeleteEventSource($Source)
                [System.Diagnostics.EventLog]::CreateEventSource($Source, $LogName)
            }
        }
        else {
            if ([System.Diagnostics.EventLog]::Exists($LogName) -eq $false) {
                $null = New-EventLog -LogName $LogName -Source $Source
            }
            else {
                [System.Diagnostics.EventLog]::CreateEventSource($Source, $LogName)
            }
        }
    }
    catch {
        Write-Warning -Message "Could not register event source '$Source' on log '$LogName' (need admin?): $($_.Exception.Message)"
        return
    }

    $autoVersion = $MyInvocation.MyCommand.Module.Version
    if ($null -eq $autoVersion) {
        $autoVersion = (Get-Module -Name 'SPSUpdate.Common' -ErrorAction SilentlyContinue).Version
    }
    $scriptVersion = if ($null -ne $autoVersion) { $autoVersion.ToString() } else { 'unknown' }
    $userName = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name

    try {
        $headerMessage = @"
SPSUpdate Version: $scriptVersion
User: $userName
ComputerName: $($env:COMPUTERNAME)
--------------------------------------------------------------
"@
        Write-EventLog -LogName $LogName -Source $Source -EventId $EventID -Message ($headerMessage + "`r`n" + $Message) -EntryType $EntryType
    }
    catch {
        Write-Warning -Message @"
SPSUpdate Version: $scriptVersion
An error occurred while writing to Event Log in Source: $Source
User: $userName
ComputerName: $($env:COMPUTERNAME)
Exception: $_
"@
    }
}
