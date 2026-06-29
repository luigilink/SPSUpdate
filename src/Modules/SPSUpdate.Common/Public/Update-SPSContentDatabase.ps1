function Update-SPSContentDatabase {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $getSPContentDb = Get-SPContentDatabase -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $getSPContentDb) {
        Write-Output "Checking Upgrading status for $($Name) ..."
        if ($getSPContentDb.NeedsUpgrade) {
            Write-Output "Upgrading SharePoint SPContentDatabase $($Name)"
            $updateStarted = Get-date
            Write-Output "Started at $updateStarted - Please Wait ..."
            if ($PSCmdlet.ShouldProcess($Name, 'Upgrade SharePoint content database')) {
                Upgrade-SPContentDatabase $Name -Confirm:$false -Verbose
            }
            $updateFinished = Get-date
            Write-Output "Update for SharePoint SPContentDatabase $($Name) is finished at $updateFinished"
        }
        else {
            Write-Output "SPContentDatabase $($Name) already upgraded - No action needed"
        }
    }
    else {
        Write-Output "SPContentDatabase $($Name) does not exist - No action needed"
    }

}
