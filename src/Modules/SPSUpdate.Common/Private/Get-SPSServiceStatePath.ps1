function Get-SPSServiceStatePath {
    <#
        .SYNOPSIS
        Builds the path of a service state file for this computer.

        .DESCRIPTION
        The name is SPSUpdate-ServicesState_<computer>_<timestamp>.json. Stop-SPSUpdateServices and
        Restore-SPSUpdateServices find the state files of an interrupted update with that pattern.

        .PARAMETER StateFolder
        Folder that holds the state files.

        .EXAMPLE
        Get-SPSServiceStatePath -StateFolder 'F:\SCRIPTS\SPSUpdate\Results'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $StateFolder
    )

    return Join-Path -Path $StateFolder -ChildPath ("SPSUpdate-ServicesState_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMddHHmmssfff').json")
}
