function Start-SPSConfigExe {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param ()

    # Check which version of SharePoint is installed
    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    $getSPInstalledProductVersion = (Get-Command $fullPath).FileVersionInfo

    if ($getSPInstalledProductVersion.FileMajorPart -eq 15) {
        $wssRegKey = 'hklm:SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\15.0\WSS'
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\15\BIN"
    }
    else {
        $wssRegKey = 'hklm:SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\16.0\WSS'
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\16\BIN"
    }
    $psconfigExe = Join-Path -Path $binaryDir -ChildPath "psconfig.exe"

    # Read LanguagePackInstalled and SetupType registry keys
    $languagePackInstalled = Get-ItemProperty -LiteralPath $wssRegKey -Name 'LanguagePackInstalled' -ErrorAction SilentlyContinue
    $setupType = Get-ItemProperty -LiteralPath $wssRegKey -Name 'SetupType'

    # Determine if LanguagePackInstalled=1 or SetupType=B2B_Upgrade.
    # If so, the Config Wizard is required
    if (($languagePackInstalled.LanguagePackInstalled -eq 1) -or ($setupType.SetupType -eq "B2B_UPGRADE")) {
        Write-Output "Starting Configuration Wizard"
        Write-Output "Starting 'Product Version Job' timer job"
        $pvTimerJob = Get-SPTimerJob -Identity 'job-admin-product-version'
        $lastRunTime = $pvTimerJob.LastRunTime

        Start-SPTimerJob -Identity $pvTimerJob

        $jobRunning = $true
        $maxCount = 30
        $count = 0
        Write-Output "Waiting for 'Product Version Job' timer job to complete"
        while ($jobRunning -and $count -le $maxCount) {
            Start-Sleep -Seconds 10

            $pvTimerJob = Get-SPTimerJob -Identity 'job-admin-product-version'
            $jobRunning = $lastRunTime -eq $pvTimerJob.LastRunTime

            $count++
        }

        # Fix for issue with psconfig on SharePoint 2019
        if ($getSPInstalledProductVersion.FileMajorPart -eq 16) {
            Upgrade-SPFarm -ServerOnly -SkipDatabaseUpgrade -SkipSiteUpgrade -Confirm:$false
        }

        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $psconfig = Start-Process -FilePath $psconfigExe `
            -ArgumentList "-cmd upgrade -inplace b2b -wait -cmd applicationcontent -install -cmd installfeatures -cmd secureresources -cmd services -install" `
            -RedirectStandardOutput $stdOutTempFile `
            -Wait `
            -PassThru

        $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
        Remove-Item -Path $stdOutTempFile

        if ($null -ne $cmdOutput) {
            Write-Output $cmdOutput.Trim()
        }

        Write-Output "PSConfig Exit Code: $($psconfig.ExitCode)"
        return $psconfig.ExitCode
    }
    # Error codes: https://aka.ms/installerrorcodes
    switch ($result) {
        0 {
            Write-Output "SharePoint Post Setup Configuration Wizard ran successfully"
        }
        Default {
            $message = ("SharePoint Post Setup Configuration Wizard failed, " + `
                    "exit code was $result. Error codes can be found at " + `
                    "https://aka.ms/installerrorcodes")
            throw $message
        }
    }
}
