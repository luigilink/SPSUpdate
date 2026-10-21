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
            [System.String]
            $WebAppName,

            [Parameter(Mandatory = $true)]
            [System.String]
            $Operation,

            [Parameter(Mandatory = $true)]
            [System.String]
            $TargetName,

            [Parameter(Mandatory = $true)]
            [ScriptBlock]
            $ApplyChange
        )

        $attempt = 0
        while ($true) {
            $attempt++
            try {
                $currentWebApp = Get-SPWebApplication -Identity $WebAppName -ErrorAction SilentlyContinue
                if ($null -eq $currentWebApp -or $null -eq $currentWebApp.WebService) {
                    throw "Could not refresh SPWebApplication '$WebAppName' before '$Operation'."
                }

                & $ApplyChange $currentWebApp.WebService
                $currentWebApp.WebService.Update()
                return $currentWebApp
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
            $currentWebApp = $webApp
            if ($EnableSideBySide) {
                if ($currentWebApp.WebService.EnableSideBySide) {
                    Write-Output "EnableSideBySide is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling EnableSideBySide on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, 'Enable SharePoint side-by-side mode')) {
                        $currentWebApp = Invoke-SPSWebServiceUpdateWithRetry -WebAppName $spWebAppName -Operation 'EnableSideBySide' -TargetName $spWebAppName -ApplyChange {
                            param($webService)
                            $webService.EnableSideBySide = $true
                        }
                    }
                }
                if ($currentWebApp.WebService.SideBySideToken -eq $BuildVersion) {
                    Write-Output "SideBySideToken $BuildVersion is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling SideBySideToken $BuildVersion on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, "Set SharePoint SideBySideToken to $BuildVersion")) {
                        $currentWebApp = Invoke-SPSWebServiceUpdateWithRetry -WebAppName $spWebAppName -Operation 'Set SideBySideToken' -TargetName $spWebAppName -ApplyChange {
                            param($webService)
                            $webService.SideBySideToken = $BuildVersion
                        }
                    }
                }
                Write-Output 'Running CmdLet Copy-SPSideBySideFiles'
                if ($PSCmdlet.ShouldProcess($spWebAppName, 'Copy SharePoint side-by-side files')) {
                    Copy-SPSideBySideFiles -Verbose
                }
            }
            else {
                if ($currentWebApp.WebService.EnableSideBySide) {
                    Write-Output "Disabling EnableSideBySide on $spWebAppName Web Application"
                    if ($PSCmdlet.ShouldProcess($spWebAppName, 'Disable SharePoint side-by-side mode')) {
                        $currentWebApp = Invoke-SPSWebServiceUpdateWithRetry -WebAppName $spWebAppName -Operation 'DisableSideBySide' -TargetName $spWebAppName -ApplyChange {
                            param($webService)
                            $webService.EnableSideBySide = $false
                        }
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
