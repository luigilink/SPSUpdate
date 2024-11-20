function Get-SPSServersPatchStatus {
    [CmdletBinding()]
    param()

    $farm = Get-SPFarm
    $productVersions = [Microsoft.SharePoint.Administration.SPProductVersions]::GetProductVersions($farm)
    $servers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }

    [array]$srvStatus = @()
    foreach ($server in $servers) {
        $serverProductInfo = $productVersions.GetServerProductInfo($server.Id)
        if ($null -ne $serverProductInfo) {
            $statusType = $serverProductInfo.InstallStatus
            if ($statusType -ne 0) {
                $statusType = $serverProductInfo.GetUpgradeStatus($farm, $server)
            }
        }
        else {
            $statusType = [Microsoft.SharePoint.Administration.SPServerProductInfo+StatusType]::NoActionRequired
        }

        $srvStatus += [PSCustomObject]@{
            Name   = $server.Name
            Status = $statusType
        }
    }
    return $srvStatus
}

function Start-SPSConfigExe {
    [CmdletBinding()]
    param ()

    # Check if all servers are on the same patch level before running psconfig.exe 
    $unpatchedServers = Get-SPSServersPatchStatus | Where-Object { $_.Status -ne "UpgradeRequired" -and $_.Status -ne "UpgradeAvailable" }
    if ($unpatchedServers.Count -eq 0) {
        Write-Verbose -Message "All servers are on the same patch level. Running PSConfig ..."
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
        $languagePackInstalled = Get-ItemProperty -LiteralPath $wssRegKey -Name 'LanguagePackInstalled'
        $setupType = Get-ItemProperty -LiteralPath $wssRegKey -Name 'SetupType'

        # Determine if LanguagePackInstalled=1 or SetupType=B2B_Upgrade.
        # If so, the Config Wizard is required
        if (($languagePackInstalled.LanguagePackInstalled -eq 1) -or ($setupType.SetupType -eq "B2B_UPGRADE")) {
            Write-Verbose -Message "Starting Configuration Wizard"
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
            $null {
                Write-Verbose -Message "No need to run SharePoint Post Setup Configuration Wizard"
            }
        }
    }
    else {
        Write-Verbose -Message "There are still some unpatched servers. Skipping running PSConfig!"
        Write-Verbose -Message "The following servers aren't on the correct patch level: $($unpatchedServers -join ", ")"
    }
}

function Start-SPSConfigExeRemote {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
        -Server $Server `
        -ScriptBlock {

        # Check if all servers are on the same patch level before running psconfig.exe 
        $unpatchedServers = Get-SPSServersPatchStatus | Where-Object { $_.Status -ne "UpgradeRequired" -and $_.Status -ne "UpgradeAvailable" }
        if ($unpatchedServers.Count -eq 0) {
            Write-Verbose -Message "All servers are on the same patch level. Running PSConfig ..."
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
            $languagePackInstalled = Get-ItemProperty -LiteralPath $wssRegKey -Name 'LanguagePackInstalled'
            $setupType = Get-ItemProperty -LiteralPath $wssRegKey -Name 'SetupType'

            # Determine if LanguagePackInstalled=1 or SetupType=B2B_Upgrade.
            # If so, the Config Wizard is required
            if (($languagePackInstalled.LanguagePackInstalled -eq 1) -or ($setupType.SetupType -eq "B2B_UPGRADE")) {
                Write-Verbose -Message "Starting Configuration Wizard"
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
                    Write-Verbose -Message $cmdOutput.Trim()
                }

                Write-Verbose -Message "PSConfig Exit Code: $($psconfig.ExitCode)"
                return $psconfig.ExitCode
            }
            else {
                return $null
            }
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
            $null {
                Write-Verbose -Message "No need to run SharePoint Post Setup Configuration Wizard"
            }
        }
    }
    else {
        Write-Verbose -Message "There are still some unpatched servers. Skipping running PSConfig!"
        Write-Verbose -Message "The following servers aren't on the correct patch level: $($unpatchedServers -join ", ")"
    }
}

function Update-SPSContentDatabase {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $getSPContentDb = Get-SPContentDatabase -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $getSPContentDb) {
        Write-Verbose -Message "Checking Upgrading status for $($Name) ..."
        if ($getSPContentDb.NeedsUpgrade) {
            Write-Verbose -Message "Upgrading SharePoint SPContentDatabase $($Name)"
            $updateStarted = Get-date
            Write-Verbose -Message "Started at $updateStarted - Please Wait ..."
            Upgrade-SPContentDatabase $Name -Confirm:$false -Verbose
            $updateFinished = Get-date
            Write-Verbose -Message "Update for SharePoint SPContentDatabase $($Name) is finished at $updateFinished"
        }
        else {
            Write-Verbose -Message "SPContentDatabase $($Name) already upgraded - No action needed"
        }
    }
    else {
        Write-Verbose -Message "SPContentDatabase $($Name) does not exist - No action needed"
    }

}

function Set-SPSSideBySideToken {
    [CmdletBinding()]
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
                    $webApp.WebService.EnableSideBySide = $true
                    $webApp.WebService.Update()
                }
                if ($webApp.WebService.SideBySideToken -eq $BuildVersion) {
                    Write-Output "SideBySideToken $BuildVersion is already enabled on $spWebAppName Web Application"
                }
                else {
                    Write-Output "Enabling SideBySideToken $BuildVersion on $spWebAppName Web Application"
                    $webApp.WebService.SideBySideToken = $BuildVersion
                    $webApp.WebService.Update()
                }
                Write-Output 'Running CmdLet Copy-SPSideBySideFiles'
                Copy-SPSideBySideFiles -Verbose
            }
            else {
                if ($webApp.WebService.EnableSideBySide) {
                    Write-Output "Disabling EnableSideBySide on $spWebAppName Web Application"
                    $webApp.WebService.EnableSideBySide = $false
                    $webApp.WebService.Update()
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
function Copy-SPSSideBySideFilesAllServers {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
    
        Write-Output "Running CmdLet Copy-SPSideBySideFiles on server: $($params.Server)"
        Copy-SPSideBySideFiles -Verbose
    }
    return $result
}
function Initialize-SPSContentDbJsonFile {
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $Path
    )

    #Initialize jSON Object, variables and class
    New-Variable -Name jsonObject `
        -Description 'jSON object variable' `
        -Option AllScope `
        -Force

    $jsonObject = [PSCustomObject]@{}
    $tbSPContentDb1 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb2 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb3 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb4 = New-Object -TypeName System.Collections.ArrayList
    class SPDbContent {
        [System.String]$Name
        [System.String]$Server
        [System.String]$WebAppUrl
    }

    #Get all content databases
    $spAllDatabases = Get-SPContentDatabase -ErrorAction SilentlyContinue

    if ($null -ne $spAllDatabases) {
        #Calculate the number of databases in each group
        $groupSize = [math]::Floor($spAllDatabases.Count / 4)
        #Loop through each content database and assign to groups
        for ($i = 0; $i -lt $spAllDatabases.Count; $i++) {
            $spDatabase = $spAllDatabases[$i]
            #Determine which group to add the database to
            if ($i -lt $groupSize) {
                [void]$tbSPContentDb1.Add([SPDbContent]@{
                        Name      = $spDatabase.Name;
                        Server    = $spDatabase.Server;
                        WebAppUrl = $spDatabase.WebApplication.Url;
                    })
            }
            elseif ($i -lt ($groupSize * 2)) {
                [void]$tbSPContentDb2.Add([SPDbContent]@{
                        Name      = $spDatabase.Name;
                        Server    = $spDatabase.Server;
                        WebAppUrl = $spDatabase.WebApplication.Url;
                    })
            }
            elseif ($i -lt ($groupSize * 3)) {
                [void]$tbSPContentDb3.Add([SPDbContent]@{
                        Name      = $spDatabase.Name;
                        Server    = $spDatabase.Server;
                        WebAppUrl = $spDatabase.WebApplication.Url;
                    })
            }
            else {
                [void]$tbSPContentDb4.Add([SPDbContent]@{
                        Name      = $spDatabase.Name;
                        Server    = $spDatabase.Server;
                        WebAppUrl = $spDatabase.WebApplication.Url;
                    })
            }
        }
        #Add each array to jsonObject
        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase1' `
            -Value $tbSPContentDb1

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase2' `
            -Value $tbSPContentDb2

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase3' `
            -Value $tbSPContentDb3

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase4' `
            -Value $tbSPContentDb4

        #Convert jsonObject to JSON and save to a file
        $jsonObject | ConvertTo-Json | Set-Content -Path $Path -Force
    }
}
