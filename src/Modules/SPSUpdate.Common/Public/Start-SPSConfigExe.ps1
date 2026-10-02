function Start-SPSConfigExe {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param ()

    # SharePoint Server Subscription Edition installs under the 16.0 hive.
    $wssRegKey = 'hklm:SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\16.0\WSS'
    $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\16\BIN"
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

        # Prepare the farm for the in-place build-to-build upgrade before running psconfig.
        Upgrade-SPFarm -ServerOnly -SkipDatabaseUpgrade -SkipSiteUpgrade -Confirm:$false

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
        if ($null -eq $psconfig -or $null -eq $psconfig.ExitCode) {
            # psconfig was required but did not return an exit code (it failed to start or
            # was interrupted). Throw so the caller records the wizard as Failed and logs an
            # error event, rather than reporting a misleading success.
            throw ("SharePoint Post Setup Configuration Wizard did not return an exit code; " + `
                    "the PSConfig run did not complete. Error codes can be found at " + `
                    "https://aka.ms/installerrorcodes")
        }
        if ($psconfig.ExitCode -ne 0) {
            # Do not throw here: a non-zero exit code is reported by psconfig for the whole
            # command chain, so a later sub-command can return non-zero even when the
            # build-to-build upgrade itself completed. The caller re-checks the authoritative
            # patch status (see Resolve-SPSWizardOutcome) before declaring a failure.
            Write-Warning -Message ("SharePoint Post Setup Configuration Wizard returned a non-zero " + `
                    "exit code ($($psconfig.ExitCode)). Error codes can be found at " + `
                    "https://aka.ms/installerrorcodes")
        }
        return $psconfig.ExitCode
    }

    # The Configuration Wizard is not required on this server (neither a language pack
    # install nor a B2B upgrade is pending); there is nothing to run, which is success.
    Write-Output "Configuration Wizard not required on this server; nothing to do."
    return 0
}
