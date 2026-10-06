function Start-SPSConfigExeRemote {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter()]
        [Switch]
        $AllowFallback
    )

    # Resolve the psconfig.exe path for the installed SharePoint version: 15.0 on SharePoint 2016,
    # 16.0 on SharePoint 2019 and Subscription Edition. The farm is homogeneous, so the master's
    # version applies to the remote server too. Defaults to the 16.0 hive when the SharePoint
    # assembly cannot be located (for example off a SharePoint host).
    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    $spMajor = 16
    if ($null -ne $fullPath) { $spMajor = ((Get-Command $fullPath).FileVersionInfo).FileMajorPart }
    if ($spMajor -eq 15) {
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\15\BIN"
    }
    else {
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\16\BIN"
    }
    $psconfigExe = Join-Path -Path $binaryDir -ChildPath "psconfig.exe"
    # Upgrade-SPFarm is needed on 2019/SE (16.0) but not on 2016 (15.0); decide on the master and
    # pass the flag into the remote script block.
    $needsFarmUpgrade = ($spMajor -ne 15)

    # Start wizard
    Write-Verbose -Message "Starting Configuration Wizard on server: $Server"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Server $Server `
        -AllowFallback:$AllowFallback `
        -Arguments @($psconfigExe, $needsFarmUpgrade) `
        -ScriptBlock {

        $psconfigExe = $args[0]
        $needsFarmUpgrade = $args[1]

        Write-Verbose -Message "Starting 'Product Version Job' timer job"
        $pvTimerJob = Get-SPTimerJob -Identity 'job-admin-product-version'
        $lastRunTime = $pvTimerJob.LastRunTime

        Start-SPTimerJob -Identity $pvTimerJob

        $jobRunning = $true
        $maxCount = 30
        $count = 0
        Write-Verbose -Message "Waiting for 'Product Version Job' timer job to complete"
        while ($jobRunning -and $count -le $maxCount) {
            Start-Sleep -Seconds 10
            $pvTimerJob = Get-SPTimerJob -Identity 'job-admin-product-version'
            $jobRunning = $lastRunTime -eq $pvTimerJob.LastRunTime
            $count++
        }

        # Fix for an issue with psconfig on SharePoint 2019 and Subscription Edition (16.0): prepare
        # the farm for the in-place build-to-build upgrade before running psconfig. Not on 2016.
        if ($needsFarmUpgrade) {
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
            Write-Verbose -Message $cmdOutput.Trim()
        }
        Write-Verbose -Message "PSConfig Exit Code: $($psconfig.ExitCode)"
        return $psconfig.ExitCode
    }
    # Require an integer exit code: if the remote script fails before psconfig returns a
    # code (for example the farm preparation step errors non-terminatingly), Invoke-SPSCommand
    # can return no usable value. Reporting that as success would mask a real failure, so throw
    # and let the caller record the wizard as Failed (and log an error event).
    $remoteExit = @($result) | Where-Object { $_ -is [int] } | Select-Object -Last 1
    if ($null -eq $remoteExit) {
        throw ("SharePoint Post Setup Configuration Wizard on '$Server' did not return an exit code; " + `
                "the remote PSConfig run did not complete. Error codes can be found at " + `
                "https://aka.ms/installerrorcodes")
    }
    # Error codes: https://aka.ms/installerrorcodes
    # Do not throw on a non-zero exit code: psconfig reports the exit code for the whole
    # command chain, so a later sub-command can return non-zero even when the
    # build-to-build upgrade itself completed. The caller re-checks the authoritative
    # patch status (see Resolve-SPSWizardOutcome) before declaring a failure. Returning
    # the exit code keeps this function consistent with Start-SPSConfigExe.
    if ($remoteExit -ne 0) {
        Write-Warning -Message ("SharePoint Post Setup Configuration Wizard on '$Server' returned a " + `
                "non-zero exit code ($remoteExit). Error codes can be found at " + `
                "https://aka.ms/installerrorcodes")
    }
    return $remoteExit
}
