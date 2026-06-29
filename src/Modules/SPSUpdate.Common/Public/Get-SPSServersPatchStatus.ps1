function Get-SPSServersPatchStatus {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server
    )

    $spFarm = Get-SPFarm
    $productVersions = [Microsoft.SharePoint.Administration.SPProductVersions]::GetProductVersions($spFarm)
    $spServer = Get-SPServer $Server
    $serverProductInfo = $productVersions.GetServerProductInfo($spServer.Id)
    if ($null -ne $serverProductInfo) {
        $statusType = $serverProductInfo.InstallStatus
        if ($statusType -ne 0) {
            $statusType = $serverProductInfo.GetUpgradeStatus($spFarm, $spServer)
        }
    }
    else {
        $statusType = [Microsoft.SharePoint.Administration.SPServerProductInfo+StatusType]::NoActionRequired
    }
    return $statusType
}
