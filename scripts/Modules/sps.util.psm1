function Clear-ComObject {
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.Object]
        $ComObject
    )

    if ($null -eq $ComObject) {
        return
    }

    try {
        if ([System.Runtime.InteropServices.Marshal]::IsComObject($ComObject)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObject)
        }
    }
    catch {
        Write-Verbose -Message "Unable to release COM object: $($_.Exception.Message)"
    }
}

function Get-SPSServersPatchStatus {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server
    )

    $spFarm = Get-SPFarm
    $productVersions = [Microsoft.SharePoint.Administration.SPProductVersions]::GetProductVersions($spFarm)
    $spServer = Get-SPServer $Server
    $serverProductInfo = $productVersions.GetServerProductInfo($spServer.Id)
    if ($null -ne $serverProductInfo) {
        $statusType = $serverProductInfo.InstallStatus
        if ($statusType -ne 0) {
            $statusType = $serverProductInfo.GetUpgradeStatus($spFarm, $spServer)
        }
    }
    else {
        $statusType = [Microsoft.SharePoint.Administration.SPServerProductInfo+StatusType]::NoActionRequired
    }
    return $statusType
}

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

function Update-SPSContentDatabase {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $getSPContentDb = Get-SPContentDatabase -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $getSPContentDb) {
        Write-Output "Checking Upgrading status for $($Name) ..."
        if ($getSPContentDb.NeedsUpgrade) {
            Write-Output "Upgrading SharePoint SPContentDatabase $($Name)"
            $updateStarted = Get-date
            Write-Output "Started at $updateStarted - Please Wait ..."
            if ($PSCmdlet.ShouldProcess($Name, 'Upgrade SharePoint content database')) {
                Upgrade-SPContentDatabase $Name -Confirm:$false -Verbose
            }
            $updateFinished = Get-date
            Write-Output "Update for SharePoint SPContentDatabase $($Name) is finished at $updateFinished"
        }
        else {
            Write-Output "SPContentDatabase $($Name) already upgraded - No action needed"
        }
    }
    else {
        Write-Output "SPContentDatabase $($Name) does not exist - No action needed"
    }

}

function Mount-SPSContentDatabase {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter()]
        [System.String]
        $DatabaseServer
    )

    # Skip mount if the content database is already attached to the farm
    $getSPContentDb = Get-SPContentDatabase -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $getSPContentDb) {
        Write-Output "SPContentDatabase $($Name) is already mounted - No action needed"
        return
    }

    # Validate that the target web application exists
    $getSPWebApp = Get-SPWebApplication -Identity $WebAppUrl -ErrorAction SilentlyContinue
    if ($null -eq $getSPWebApp) {
        $catchMessage = "SPWebApplication '$WebAppUrl' was not found - Cannot mount SPContentDatabase '$Name'"
        Add-SPSUpdateEvent -Message $catchMessage -Source 'Mount-SPSContentDatabase' -EntryType 'Error'
        throw $catchMessage
    }

    Write-Output "Mounting SPContentDatabase $($Name) on WebApplication $($WebAppUrl)"
    $mountStarted = Get-Date
    Write-Output "Started at $mountStarted - Please Wait ..."
    if ($PSCmdlet.ShouldProcess($Name, "Mount SharePoint content database on $WebAppUrl")) {
        $mountParams = @{
            Name           = $Name
            WebApplication = $WebAppUrl
            Confirm        = $false
        }
        if (-not [string]::IsNullOrWhiteSpace($DatabaseServer)) {
            $mountParams['DatabaseServer'] = $DatabaseServer
        }
        Mount-SPContentDatabase @mountParams -Verbose
    }
    $mountFinished = Get-Date
    Write-Output "Mount for SPContentDatabase $($Name) is finished at $mountFinished"
}

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
function Copy-SPSSideBySideFilesRemote {
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

Set-Alias -Name Copy-SPSSideBySideFilesAllServers -Value Copy-SPSSideBySideFilesRemote
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
        # --- LPT (Longest Processing Time First) scheduling ---
        # Balance databases across 4 sequences by total DiskSizeRequired
        # rather than by count, so parallel upgrade workloads finish closer
        # to the same time.

        # 1. Sort databases by size descending
        $spSortedDatabases = $spAllDatabases |
            Sort-Object -Property DiskSizeRequired -Descending

        # 2. Track cumulative load (bytes) per sequence (index 0 = Seq1 .. 3 = Seq4)
        $sequenceLoad  = @(0.0, 0.0, 0.0, 0.0)
        $sequenceLists = @($tbSPContentDb1, $tbSPContentDb2, $tbSPContentDb3, $tbSPContentDb4)

        # 3. Assign each database to the sequence with the lowest current load
        foreach ($spDatabase in $spSortedDatabases) {
            $minLoad  = $sequenceLoad[0]
            $minIndex = 0
            for ($s = 1; $s -lt 4; $s++) {
                if ($sequenceLoad[$s] -lt $minLoad) {
                    $minLoad  = $sequenceLoad[$s]
                    $minIndex = $s
                }
            }
            [void]$sequenceLists[$minIndex].Add([SPDbContent]@{
                    Name      = $spDatabase.Name;
                    Server    = $spDatabase.Server;
                    WebAppUrl = $spDatabase.WebApplication.Url;
                })
            $sequenceLoad[$minIndex] += $spDatabase.DiskSizeRequired
        }

        # --- Distribution report (visible in transcript) ---
        $totalBytes = ($sequenceLoad | Measure-Object -Sum).Sum
        $totalMB    = [math]::Round($totalBytes / 1MB, 0)
        $dbCount    = @($spSortedDatabases).Count
        Write-Output '--- ContentDatabase Distribution Report ---'
        Write-Output ("Total : {0} database(s) | {1:N0} MB" -f $dbCount, $totalMB)
        for ($s = 0; $s -lt 4; $s++) {
            $loadMB = [math]::Round($sequenceLoad[$s] / 1MB, 0)
            $pct    = if ($totalBytes -gt 0) {
                [math]::Round($sequenceLoad[$s] / $totalBytes * 100, 1)
            }
            else { 0 }
            Write-Output ("  Sequence {0} : {1,3} database(s) | {2,7:N0} MB | {3,5:N1}%" `
                    -f ($s + 1), $sequenceLists[$s].Count, $loadMB, $pct)
        }
        Write-Output '-------------------------------------------'

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

        # Serialize once and write both the canonical file (consumed by SPSUpdate.ps1)
        # and a timestamped snapshot in the same folder so previous inventories are
        # retained for troubleshooting and rollback.
        $jsonPayload = $jsonObject | ConvertTo-Json
        $jsonPayload | Set-Content -Path $Path -Force

        try {
            $snapshotDir       = [System.IO.Path]::GetDirectoryName($Path)
            $snapshotBaseName  = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $snapshotExtension = [System.IO.Path]::GetExtension($Path)
            $snapshotTimestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
            $snapshotFileName  = '{0}_{1}{2}' -f $snapshotBaseName, $snapshotTimestamp, $snapshotExtension
            $snapshotPath      = if ([string]::IsNullOrEmpty($snapshotDir)) {
                $snapshotFileName
            }
            else {
                Join-Path -Path $snapshotDir -ChildPath $snapshotFileName
            }
            $jsonPayload | Set-Content -Path $snapshotPath -Force
            Write-Output "ContentDatabase inventory snapshot saved to: $snapshotPath"
        }
        catch {
            Write-Verbose -Message "Failed to write ContentDatabase inventory snapshot: $($_.Exception.Message)"
        }
    }
}

function Get-SPSLocalVersionInfo {
    [OutputType([System.Version])]
    param
    (
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [ValidateSet('2016', '2019', 'SE')]
        [System.String]
        $ProductVersion,

        [Parameter()]
        [Switch]
        $IsWssPackage
    )

    if ($ProductVersion -eq 'SE') {
        $spVersion = 'Subscription Edition'
    }
    else {
        $spVersion = $ProductVersion
    }

    $productNameRegEx = "Microsoft SharePoint (Foundation|Server) $($spVersion) Core"
    if ($IsWssPackage) {
        $productNameRegEx = "Microsoft SharePoint (Foundation|Server) $($spVersion) \d{4} (Lang|Language) Pack"
    }
    Write-Verbose "Product Name RegEx: $($productNameRegEx)"
    $installerRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products"
    $patchRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Patches"
    $installerEntries = Get-ChildItem -Path $installerRegistryPath -ErrorAction SilentlyContinue
    $nullVersion = New-Object -TypeName System.Version
    $versionInfoValue = New-Object -TypeName System.Version
    $officeProductKeys = $installerEntries | Where-Object -FilterScript { $_.PsPath -like "*00000000F01FEC" }

    if ($null -eq $installerEntries -or $null -eq $officeProductKeys ) {
        return $nullVersion
    }

    # $null - one command returns an empty value
    $null = $officeProductKeys | ForEach-Object -Process {
        $officeProductKey = $_
        $productInfo = Get-ItemProperty "Registry::$($officeProductKey)\InstallProperties" -ErrorAction SilentlyContinue
        if ($null -eq $productInfo) {
            return
        }
        $prodName = $productInfo.DisplayName
        if ($prodName -match $productNameRegEx) {
            Write-Verbose "Gathering Information for $($prodName)"
            $versionInfo = $nullVersion
            $patchInformationFolder = Get-ItemProperty "Registry::$($officeProductKey)\Patches"
            $patchGuid = $patchInformationFolder.AllPatches
            if ($null -ne $patchGuid) {
                $detailedPatchInformation = Get-ItemProperty "$($patchRegistryPath)\$($patchGuid)" -ErrorAction SilentlyContinue
                $localPackage = $detailedPatchInformation.LocalPackage
                if ($null -ne $localPackage) {
                    $patchFileInformation = New-Object -TypeName System.IO.FileInfo -ArgumentList $localPackage
                    if ($patchFileInformation.Extension -eq ".msp") {
                        try {
                            $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
                            $installerDatabase = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, ($localPackage , 32))
                            $databaseQuery = "SELECT Value FROM MsiPatchMetadata WHERE Property = 'BuildNumber'"
                            $databaseView = $installerDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $installerDatabase, ($databaseQuery))
                            $databaseView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $databaseView, $null)
                            $value = $databaseView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $databaseView, $null)
                            $versionInfo = [System.Version]$value.GetType().InvokeMember("StringData", "GetProperty", $null, $value, 1)
                            Clear-ComObject -ComObject $databaseView
                            Clear-ComObject -ComObject $value
                            Clear-ComObject -ComObject $installerDatabase
                            Clear-ComObject -ComObject $windowsInstaller
                        }
                        catch [Exception] {
                            $catchMessage = @"
An error occurred during the collection of data about installed products in Get-SPSLocalVersionInfo.
Exception: $($_.Exception.Message)
"@
                            Write-Error -Message $catchMessage
                            Add-SPSUpdateEvent -Message $catchMessage -Source 'Get-SPSLocalVersionInfo' -EntryType 'Error'
                            $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                        }
                    }
                    else {
                        $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                    }
                }
                else {
                    $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                }
            }
            else {
                $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
            }
            # Collect Information about language packs
            if ($IsWssPackage -and (  $versionInfoValue -eq $nullVersion -or $versionInfoValue -gt $versionInfo)) {
                $versionInfoValue = $versionInfo
            }
            else {
                $versionInfoValue = $versionInfo
            }
            Write-Verbose "Version Information for $($prodName): $($versionInfoValue)"
        }
    }

    if ($nullVersion -ne $versionInfoValue) {
        return $versionInfoValue
    }

    return $nullVersion
}

function Start-SPSProductUpdate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SetupFile,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $ShutdownServices
    )

    Write-Verbose -Message "Getting install status of SP binaries"
    Write-Verbose -Message "Check if the setup file exists"
    if (-Not (Test-Path -Path $SetupFile)) {
        Throw "ERROR: Setup files could not be found: $SetupFile"
    }

    Write-Verbose -Message "Checking file status of $SetupFile"
    Write-Verbose -Message "Checking status now"
    try {
        $zone = Get-Item -Path $SetupFile -Stream "Zone.Identifier" -EA SilentlyContinue
    }
    catch {
        Write-Verbose -Message 'Encountered error while reading file stream. Ignoring file stream.'
    }

    if ($null -ne $zone) {
        $catchMessage = @"
Setup file is blocked! Please use 'Unblock-File -Path $SetupFile' to unblock the file before continuing.
"@
        Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSProductUpdate' -EntryType 'Error'
        throw $catchMessage
    }
    Write-Verbose -Message "File not blocked, continuing."
    Write-Verbose -Message "Get file information from setup file"
    $setupFileInfo = Get-ItemProperty -Path $SetupFile
    $fileVersion = $setupFileInfo.VersionInfo.FileVersion
    Write-Verbose -Message "Update has version $fileVersion"
    $fileVersionInfo = New-Object -TypeName System.Version -ArgumentList $fileVersion
    if ($fileVersionInfo.Build.ToString().Length -eq 4) {
        $sharePointVersion = '2016'
    }
    else {
        if ($fileVersionInfo.Build -lt 13000) {
            $sharePointVersion = '2019'
        }
        else {
            $sharePointVersion = 'SE'
        }
    }
    
    Write-Verbose -Message "Update is a Cumulative Update."
    # For SP 2016 + 2019 Patches
    $setupFileInformation = New-Object -TypeName System.IO.FileInfo -ArgumentList  $SetupFile
    if ($setupFileInformation.Name.StartsWith("wssloc")) {
        Write-Verbose -Message "Cumulative Update is multilingual"
        $versionInfo = Get-SPSLocalVersionInfo -ProductVersion $sharePointVersion -IsWssPackage
    }
    else {
        Write-Verbose -Message "Cumulative Update is generic"
        $versionInfo = Get-SPSLocalVersionInfo -ProductVersion $sharePointVersion
    }

    Write-Verbose -Message "The lowest version of any SharePoint component is $($versionInfo)"
    if ($versionInfo -lt $fileVersionInfo) {
        # Version of SharePoint is lower than the patch version. Patch is not installed.
        Write-Verbose -Message "The version of SharePoint installed is lower than the update. Starting update process."
        $installedVersion = Get-SPSInstalledProductVersion
        if ($ShutdownServices) {
            $listOfServices = @("SPSearchHostController", "SPTimerV4", "IISADMIN")
            if ($installedVersion.ProductMajorPart -eq 15) {
                
                $listOfServices += "OSearch15"
            }
            else {
                $listOfServices += "OSearch16"
            }
            Write-Verbose -Message "Gettings services status before stopping services for installation."
            $servicesStatusFilePath = Join-Path -Path $PSScriptRoot -ChildPath "ServicesStatus_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMddHHmmss').json"
            Get-Service -Name $listOfServices -ErrorAction SilentlyContinue | Select-Object Name, StartType, Status | ConvertTo-Json | Set-Content -Path $servicesStatusFilePath -Force
            Write-Verbose -Message "Services status saved to $servicesStatusFilePath"
            Write-Verbose -Message "Stopping services to speed up installation process"
            foreach ($service in $listOfServices) {
                Write-Verbose -Message "Stopping service: $service - Setting startup type to disabled"
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            }
            write-Verbose -Message "All services stopped. Starting installation process."
            $null = Start-Process -FilePath "iisreset.exe" `
                -ArgumentList "-stop -noforce" `
                -Wait `
                -PassThru


        }

        $setupInstall = Start-Process -FilePath $SetupFile -ArgumentList '/passive' -Wait -PassThru
        # Error codes: https://aka.ms/installerrorcodes
        switch ($setupInstall.ExitCode) {
            0 {
                Write-Verbose -Message "SharePoint update binary installation complete."
            }
            17022 {
                Write-Verbose -Message ("SharePoint update binary installation complete, however a reboot is required.")
            }
            17025 {
                Write-Verbose -Message ("The SharePoint update was already installed on your system." + `
                        "Please report an issue about this behavior at https://github.com/dsccommunity/SharePointDsc")
            }
            Default {
                $catchMessage = @"
SharePoint update install failed, exit code was $($setupInstall.ExitCode).
Error codes can be found at https://aka.ms/installerrorcodes
"@                
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSProductUpdate' -EntryType 'Error'
                throw $catchMessage
            }
        }
        if ($ShutdownServices) {
            Write-Verbose -Message "Getting services status from json configuration."
            $servicesStatusFromFile = Get-Content -Path $servicesStatusFilePath -Raw | ConvertFrom-Json
            foreach ($service in $servicesStatusFromFile) {
                Write-Verbose -Message "Service: $($service.Name) - Startup Type before installation: $($service.StartType) - Status before installation: $($service.Status)"
                if ($service.Status -ne "Running") {
                    Write-Verbose -Message "Service: $($service.Name) was not running before installation. Keeping it stopped."
                    Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose -Message "Service: $($service.Name) was running before installation. Restoring its startup type."
                    Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction SilentlyContinue
                    Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                }
            }
            Start-Process -FilePath "iisreset.exe" `
                -ArgumentList "-start" `
                -Wait `
                -PassThru
            write-Verbose -Message "All services started. Installation process complete."
        }
    }
    else {
        # Version of SharePoint is equal or greater than the patch version. Patch is installed.
        Write-Verbose -Message "The version of SharePoint installed is equal or higher than the update. No action needed."
    }
}
