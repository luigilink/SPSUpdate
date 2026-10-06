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

    # SharePoint Server Subscription Edition installs under the 16.0 hive.
    $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\16\BIN"
    $psconfigExe = Join-Path -Path $binaryDir -ChildPath "psconfig.exe"

    # Start wizard
    Write-Verbose -Message "Starting Configuration Wizard on server: $Server"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Server $Server `
        -AllowFallback:$AllowFallback `
        -Arguments $psconfigExe `
        -ScriptBlock {

        $psconfigExe = $args[0]

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
