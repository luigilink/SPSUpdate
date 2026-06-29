function Start-SPSConfigExeRemote {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    # Check which version of SharePoint is installed
    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    $getSPInstalledProductVersion = (Get-Command $fullPath).FileVersionInfo

    if ($getSPInstalledProductVersion.FileMajorPart -eq 15) {
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\15\BIN"
    }
    else {
        $binaryDir = Join-Path $env:CommonProgramFiles "Microsoft Shared\Web Server Extensions\16\BIN"
    }
    $psconfigExe = Join-Path -Path $binaryDir -ChildPath "psconfig.exe"

    # Start wizard
    Write-Verbose -Message "Starting Configuration Wizard on server: $Server"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Server $Server `
        -Arguments $psconfigExe `
        -ScriptBlock {

        $psconfigExe = $args[0]

        # Check which version of SharePoint is installed
        $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
        $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
        $getSPInstalledProductVersion = (Get-Command $fullPath).FileVersionInfo

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

        # Fix for issue with psconfig on SharePoint 2019
        if ($getSPInstalledProductVersion.FileMajorPart -ne 15) {
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
    # Error codes: https://aka.ms/installerrorcodes
    switch ($result) {
        0 {
            Write-Verbose -Message "SharePoint Post Setup Configuration Wizard ran successfully"
        }
        Default {
            $message = ("SharePoint Post Setup Configuration Wizard failed, " + `
                    "exit code was $result. Error codes can be found at " + `
                    "https://aka.ms/installerrorcodes")
            throw $message
        }
    }
}
