function Mount-SPSContentDatabase {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter()]
        [System.String]
        $DatabaseServer
    )

    # Skip mount if the content database is already attached to the farm
    $getSPContentDb = Get-SPContentDatabase -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $getSPContentDb) {
        Write-Output "SPContentDatabase $($Name) is already mounted - No action needed"
        return
    }

    # Validate that the target web application exists
    $getSPWebApp = Get-SPWebApplication -Identity $WebAppUrl -ErrorAction SilentlyContinue
    if ($null -eq $getSPWebApp) {
        $catchMessage = "SPWebApplication '$WebAppUrl' was not found - Cannot mount SPContentDatabase '$Name'"
        Add-SPSUpdateEvent -Message $catchMessage -Source 'Mount-SPSContentDatabase' -EntryType 'Error'
        throw $catchMessage
    }

    Write-Output "Mounting SPContentDatabase $($Name) on WebApplication $($WebAppUrl)"
    $mountStarted = Get-Date
    Write-Output "Started at $mountStarted - Please Wait ..."
    if ($PSCmdlet.ShouldProcess($Name, "Mount SharePoint content database on $WebAppUrl")) {
        $mountParams = @{
            Name           = $Name
            WebApplication = $WebAppUrl
            Confirm        = $false
        }
        if (-not [string]::IsNullOrWhiteSpace($DatabaseServer)) {
            $mountParams['DatabaseServer'] = $DatabaseServer
        }
        Mount-SPContentDatabase @mountParams -Verbose
    }
    $mountFinished = Get-Date
    Write-Output "Mount for SPContentDatabase $($Name) is finished at $mountFinished"
}
