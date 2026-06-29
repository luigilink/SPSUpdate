function Set-SPSSideBySideToken {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter()]
        [System.String]
        $BuildVersion,

        [Parameter()]
        [System.Boolean]
        $EnableSideBySide
    )

    $webApps = Get-SPWebApplication -ErrorAction SilentlyContinue
    if ($null -ne $webApps) {
        foreach ($webApp in $webApps) {
            $spWebAppName = $webApp.Name
            if ($EnableSideBySide) {
                if ($webApp.WebService.EnableSideBySide) {
                    Write-Output "EnableSideBySide is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling EnableSideBySide on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, 'Enable SharePoint side-by-side mode')) {
                        $webApp.WebService.EnableSideBySide = $true
                        $webApp.WebService.Update()
                    }
                }
                if ($webApp.WebService.SideBySideToken -eq $BuildVersion) {
                    Write-Output "SideBySideToken $BuildVersion is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling SideBySideToken $BuildVersion on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, "Set SharePoint SideBySideToken to $BuildVersion")) {
                        $webApp.WebService.SideBySideToken = $BuildVersion
                        $webApp.WebService.Update()
                    }
                }
                Write-Output 'Running CmdLet Copy-SPSideBySideFiles'
                if ($PSCmdlet.ShouldProcess($spWebAppName, 'Copy SharePoint side-by-side files')) {
                    Copy-SPSideBySideFiles -Verbose
                }
            }
            else {
                if ($webApp.WebService.EnableSideBySide) {
                    Write-Output "Disabling EnableSideBySide on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, 'Disable SharePoint side-by-side mode')) {
                        $webApp.WebService.EnableSideBySide = $false
                        $webApp.WebService.Update()
                    }
                }
                else {
                    Write-Output "EnableSideBySide is already disabled on $spWebAppName Web Application"
                }
            }
        }
    }
    else {
        throw 'Did not find SPWebApplication Object'
    }
}
