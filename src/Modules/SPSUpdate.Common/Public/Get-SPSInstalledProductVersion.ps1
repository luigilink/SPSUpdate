function Get-SPSInstalledProductVersion {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.FileVersionInfo])]
    param ()

    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    if ($null -eq $fullPath) {
        Write-Error -Message 'SharePoint path {C:\Program Files\Common Files\microsoft shared\Web Server Extensions} does not exist'
    }
    else {
        return [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath.FullName)
    }
}
