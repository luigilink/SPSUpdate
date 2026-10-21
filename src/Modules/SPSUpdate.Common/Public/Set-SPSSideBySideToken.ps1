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

    $maxUpdateConflictAttempts = 6
    $updateConflictRetryDelaySeconds = 15

    function Invoke-SPSWebServiceUpdateWithRetry {
        param
        (
            [Parameter(Mandatory = $true)]
            $WebService,

            [Parameter(Mandatory = $true)]
            [System.String]
            $Operation,

            [Parameter(Mandatory = $true)]
            [System.String]
            $TargetName
        )

        $attempt = 0
        while ($true) {
            $attempt++
            try {
                $WebService.Update()
                return
            }
            catch {
                $isConflict = $_.Exception.Message -match '(?i)update conflict has occurred'
                if (-not $isConflict -or $attempt -ge $maxUpdateConflictAttempts) {
                    throw
                }

                Write-Warning "SPWebService update conflict during '$Operation' on '$TargetName' (attempt $attempt/$maxUpdateConflictAttempts). Retrying in $updateConflictRetryDelaySeconds seconds."
                Start-Sleep -Seconds $updateConflictRetryDelaySeconds
            }
        }
    }

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
                        Invoke-SPSWebServiceUpdateWithRetry -WebService $webApp.WebService -Operation 'EnableSideBySide' -TargetName $spWebAppName
                    }
                }
                if ($webApp.WebService.SideBySideToken -eq $BuildVersion) {
                    Write-Output "SideBySideToken $BuildVersion is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling SideBySideToken $BuildVersion on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, "Set SharePoint SideBySideToken to $BuildVersion")) {
                        $webApp.WebService.SideBySideToken = $BuildVersion
                        Invoke-SPSWebServiceUpdateWithRetry -WebService $webApp.WebService -Operation 'Set SideBySideToken' -TargetName $spWebAppName
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
                        Invoke-SPSWebServiceUpdateWithRetry -WebService $webApp.WebService -Operation 'DisableSideBySide' -TargetName $spWebAppName
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
