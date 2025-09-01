<#
    .SYNOPSIS
    SPSUpdate script for SharePoint Server.

    .DESCRIPTION
    SPSUpdate is a PowerShell script tool designed to install cumulative updates in your SharePoint environment.
    It's compatible with PowerShell version 5.1 and later.

    .PARAMETER ConfigFile
    Need parameter ConfigFile, example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json'

    .PARAMETER Sequence
    Need parameter Sequence for SPS Farm, example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Sequence 1

    .PARAMETER Install
    Use the switch Install parameter if you want to add the SPSUpdate script in taskscheduler
    InstallAccount parameter need to be set
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use the switch Install parameter
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'

    .PARAMETER Uninstall
    Use the switch Uninstall parameter if you want to remove the SPSUpdate script from taskscheduler
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Uninstall

    .EXAMPLE
    SPSUpdate.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'
    SPSUpdate.ps1 -Uninstall -ConfigFile 'contoso-PROD.json'

    .NOTES
    FileName:	SPSUpdate.ps1
    Author:		Jean-Cyril DROUHIN
    Date:		August 19, 2025
    Version:	1.0.1

    .LINK
    https://spjc.fr/
    https://github.com/luigilink/SPSUpdate
#>
param
(
    [Parameter(Position = 1, Mandatory = $true)]
    [ValidateScript({ (Test-Path $_) -and ($_ -like '*.json') })]
    [System.String]
    $ConfigFile, # Path to the configuration file

    [Parameter(Position = 2)]
    [ValidateRange(1, 4)]
    [System.UInt32]
    $Sequence,

    [Parameter(Position = 3)]
    [switch]
    $Install, # Switch parameter to add scheduled tasks

    [Parameter(Position = 4)]
    [System.Management.Automation.PSCredential]
    $InstallAccount, # Credential for the InstallAccount

    [Parameter(Position = 5)]
    [switch]
    $Uninstall # Switch parameter to remove scheduled tasks
)

#region Initialization
# Clear the host console
Clear-Host

# Set the window title
$Host.UI.RawUI.WindowTitle = "SPSTrust script running on $env:COMPUTERNAME"

# Define the path to the helper module
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:HelperModulePath = Join-Path -Path $scriptRootPath -ChildPath 'Modules'

# Import the helper module
Import-Module -Name (Join-Path -Path $script:HelperModulePath -ChildPath 'util.psm1') -Force

# Import the credentialmanager module
Import-Module -Name (Join-Path -Path (Join-Path -Path $script:HelperModulePath -ChildPath 'credentialmanager') -ChildPath 'CredentialManager.psd1') -Force

# Ensure the script is running with administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Throw "Administrator rights are required. Please re-run this script as an Administrator."
}

# Load the configuration file
try {
    if (Test-Path $ConfigFile) {
        $jsonEnvCfg = Get-Content $ConfigFile | ConvertFrom-Json
        $Application = $jsonEnvCfg.ApplicationName
        $Environment = $jsonEnvCfg.ConfigurationName
        $scriptFQDN = $jsonEnvCfg.Domain
        $spFarmName = $jsonEnvCfg.FarmName
    }
    else {
        Throw "Configuration file '$ConfigFile' not found."
    }
}
catch {
    Write-Error "Failed to load configuration file: $_"
    Exit
}

# Define variables
$SPSUpdateVersion = '1.0.1'
$getDateFormatted = Get-Date -Format yyyy-MM-dd_H-mm
$spsUpdateFileName = "$($Application)-$($Environment)_$($getDateFormatted)"
$spsUpdateDBsFile = "$($Application)-$($Environment)-$($spFarmName)-ContentDBs.json"
$currentUser = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
$pathLogsFolder = Join-Path -Path $scriptRootPath -ChildPath 'Logs'
$pathConfigFolder = Join-Path -Path $scriptRootPath -ChildPath 'Config'
$fullScriptPath = Join-Path -Path $scriptRootPath -ChildPath 'SPSUpdate.ps1'
$spsUpdateDBsPath = Join-Path -Path $pathConfigFolder -ChildPath $spsUpdateDBsFile

# Initialize logs
if (-Not (Test-Path -Path $pathLogsFolder)) {
    New-Item -ItemType Directory -Path $pathLogsFolder -Force
}
if ($Sequence) {
    $pathLogFile = Join-Path -Path $pathlogsFolder -ChildPath ("$($Application)-$($Environment)_Sequence$($Sequence)_" + (Get-Date -Format yyyy-MM-dd_H-mm) + '.log')
}
else {
    $pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ($spsUpdateFileName + '.log')
}
$DateStarted = Get-Date
$psVersion = ($Host).Version.ToString()

# Start transcript to log the output
Start-Transcript -Path $pathLogFile -IncludeInvocationHeader

# Output the script information
Write-Output '-----------------------------------------------'
Write-Output "| SPSUpdate Script - v$SPSUpdateVersion"
Write-Output "| Started on - $DateStarted by $currentUser"
Write-Output "| PowerShell Version - $psVersion"
Write-Output '-----------------------------------------------'
#endregion

#region Main Process

# 0. Set power management plan to "High Performance"
Write-Verbose -Message "Setting power management plan to 'High Performance'..."
Start-Process -FilePath "$env:SystemRoot\system32\powercfg.exe" -ArgumentList '/s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -NoNewWindow

# 1. Load SharePoint Powershell Snapin or Import-Module
try {
    $installedVersion = Get-SPSInstalledProductVersion
    if ($installedVersion.ProductMajorPart -eq 15 -or $installedVersion.ProductBuildPart -le 12999) {
        if ($null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
            Add-PSSnapin Microsoft.SharePoint.PowerShell
        }
    }
    else {
        Import-Module SharePointServer -Verbose:$false -WarningAction SilentlyContinue
    }
}
catch {
    # Handle errors during retrieval of Installed Product Version
    Write-Error -Message @"
Failed to get installed Product Version for $($env:COMPUTERNAME)
Exception: $_
"@
}

# 2. Initialize or read ContentDatabase json file if UpgradeContentDatabase equal to true
try {
    if ($jsonEnvCfg.UpgradeContentDatabase) {
        if (-Not (Test-Path -Path $pathConfigFolder)) {
            # If the path does not exist, create the directory
            New-Item -ItemType Directory -Path $pathConfigFolder
        }
        if (Test-Path $spsUpdateDBsPath) {
            Write-Output "Get ContentDatabase json file for SPFARM: $($spFarmName)"
            $jsonDbCfg = Get-Content $spsUpdateDBsPath | ConvertFrom-Json
        }
        else {
            # Initialize contentDb json file
            "Initialize ContentDatabase json file for SPFARM: $($spFarmName)"
            Initialize-SPSContentDbJsonFile -Path $spsUpdateDBsPath
            $jsonDbCfg = Get-Content $spsUpdateDBsPath | ConvertFrom-Json
        }
    }
}
catch {
    # Handle errors during Initialize ContentDatabase json file
    Write-Error -Message @"
Failed to Initialize ContentDatabase json file for SPFARM: $($spFarmName)
Exception: $_
"@
}

# Check UserName and Password if Install parameter is used
if ($Install) {
    if ($null -eq $InstallAccount) {
        Write-Warning -Message ('SPSUpdate: Install parameter is set. Please set also InstallAccount ' + `
                "parameter. `nSee https://github.com/luigilink/SPSUpdate/wiki for details.")
        Break
    }
    else {
        $UserName = $InstallAccount.UserName
        $Password = $InstallAccount.GetNetworkCredential().Password
        $currentDomain = 'LDAP://' + ([ADSI]'').distinguishedName
        Write-Output "Checking Account `"$UserName`" ..."
        $dom = New-Object System.DirectoryServices.DirectoryEntry($currentDomain, $UserName, $Password)
        if ($null -eq $dom.Path) {
            Write-Warning -Message "Password Invalid for user:`"$UserName`""
            Break
        }
        else {
            # Add Credential in Credential Manager
            try {
                $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
                if ($null -eq $credential) {
                    New-StoredCredential -Credentials $InstallAccount -Target "$($jsonEnvCfg.StoredCredential)" -Type Generic -Persist LocalMachine
                }
            }
            catch {
                # Handle errors during Get or Add Credential in Crededential Manager
                Write-Error -Message @"
Failed to Get or Add Credential in Crededential Manager for SPFarm: $($spFarmName)
Exception: $_
"@
            }
            # Add scheduled Task for Update Full Script
            try {
                # Initialize ActionArguments parameter
                $ActionArguments = "-ExecutionPolicy Bypass -File `"$($fullScriptPath)`" -ConfigFile `"$($ConfigFile)`" -Verbose"
                Write-Output 'Adding Scheduled Task SPSUpdate-FullScript in SharePoint Task Path'
                Add-SPSScheduledTask -Name 'SPSUpdate-FullScript' `
                    -Description 'Scheduled Task for Update SharePoint Server after installation of cumulative update' `
                    -ActionArguments $ActionArguments `
                    -ExecuteAsCredential $InstallAccount
            }
            catch {
                # Handle errors during Add scheduled Task for Update Full Script
                Write-Error -Message @"
Failed to Add Scheduled Task in SharePoint Task Path for SPFarm: $($spFarmName)
Exception: $_
"@
            }
        }
    }
}
elseif ($Uninstall) {
    # Remove scheduled Task for Update Full Script
    try {
        Write-Output 'Removing Scheduled Task SPSUpdate-FullScript in SharePoint Task Path'
        Remove-SPSScheduledTask -Name 'SPSUpdate-FullScript'
        foreach ($taskId in (1..4)) {
            Write-Output "Removing Scheduled Tasks SPSUpdate-Sequence$taskId in SharePoint Task Path"
            Remove-SPSScheduledTask -Name "SPSUpdate-Sequence$taskId"
        }
    }
    catch {
        # Handle errors during Remove scheduled Task for Update Full Script
        Write-Error -Message @"
Failed to Remove Scheduled Task in SharePoint Task Path for SPFarm: $($spFarmName)
Exception: $_
"@
    }
    # Remove Credential from Credential Manager
    try {
        $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
        if ($null -ne $credential) {
            Remove-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)"
        }
    }
    catch {
        # Handle errors during Get or Remove Credential in Crededential Manager
        Write-Error -Message @"
Failed to Get or Remove Credential in Crededential Manager for SPFarm: $($spFarmName)
Exception: $_
"@
    }

}
else {
    if ($Sequence -ne 0) {
        try {
            Write-Output "Update Script in progress | Sequence $Sequence  - Please Wait ..."
            switch ($Sequence) {
                1 { $dbs = $jsonDbCfg.SPContentDatabase1 }
                2 { $dbs = $jsonDbCfg.SPContentDatabase2 }
                3 { $dbs = $jsonDbCfg.SPContentDatabase3 }
                4 { $dbs = $jsonDbCfg.SPContentDatabase4 }
            }
            foreach ($db in $dbs) {
                Update-SPSContentDatabase -Name $db.Name
            }
        }
        catch {
            # Handle errors during Update Script Sequence
            Write-Error -Message @"
Failed to Upgrade SPContentDatabse '$($db.Name)' during sequence: $($Sequence)
Target SPFarm: $($spFarmName)
Exception: $_
"@
        }

    }
    else {
        # Initialize Security
        $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
        if ($null -ne $credential) {
            New-Variable -Name 'ADM' -Value $credential -Force
        }
        else {
            Throw "The Target $($jsonEnvCfg.StoredCredential) not present in Credential Manager. Please contact your administrator."
        }
        Write-Output "Update Script in progress | FULL Mode - Please Wait ..."
        # Update SPContentDatabase
        if ($jsonEnvCfg.UpgradeContentDatabase) {
            # Add scheduled Task for Upgrade SPContentDatabase in Parallel
            foreach ($taskId in (1..4)) {
                try {
                    # Initialize ActionArguments parameter
                    $ActionArguments = "-ExecutionPolicy Bypass -File `"$($fullScriptPath)`" -ConfigFile `"$($ConfigFile)`" -Sequence $taskId -Verbose"
                    Write-Output "Adding Scheduled Tasks SPSUpdate-Sequence$taskId in SharePoint Task Path"
                    Add-SPSScheduledTask -Name "SPSUpdate-Sequence$taskId" `
                        -Description "Scheduled Task Sequence$taskId for Update SharePoint Server after installation of cumulative update" `
                        -ActionArguments $ActionArguments `
                        -ExecuteAsCredential $ADM
                }
                catch {
                    # Handle errors during Add scheduled Task for Update Full Script
                    Write-Error -Message @"
Failed to Add Scheduled Task in SharePoint Task Path
Task Name: SPSUpdate-Sequence$taskId
Target SPFarm: $($spFarmName)
Exception: $_
"@
                }
            }

            # Run scheduled Task for Upgrade SPContentDatabase in Parallel
            foreach ($taskId in (1..4)) {
                try {
                    Write-Output "Running Scheduled Tasks SPSUpdate-Sequence$taskId in SharePoint Task Path"
                    Start-SPSScheduledTask -Name "SPSUpdate-Sequence$taskId"
                    Write-Output 'Avoid conflicts with OWSTimer process - Pause between 60 to 90 seconds'
                    Start-Sleep -Seconds (get-random (60..90))
                }
                catch {
                    # Handle errors during Start scheduled Task for Upgrade SPContentDatabase in Parallel
                    Write-Error -Message @"
Failed to Start Scheduled Task in SharePoint Task Path
Task Name: SPSUpdate-Sequence$taskId
Target SPFarm: $($spFarmName)
Exception: $_
"@
                }

            }

            # Wait until all scheduled Tasks are finished
            # Define list variable of scheduled tasks
            $scheduledTasks = @('SPSUpdate-Sequence1', 'SPSUpdate-Sequence2', 'SPSUpdate-Sequence3', 'SPSUpdate-Sequence4')

            # Continuously check the status of tasks until all are finished
            $allTasksFinished = $false
            while (-not $allTasksFinished) {
                $allTasksFinished = $true
                foreach ($scheduledTask in $scheduledTasks) {
                    $taskStatus = Get-ScheduledTask -TaskName $scheduledTask | Select-Object State
                    if ($taskStatus.State -ne 'Running') {
                        Write-Output "Scheduled Task $($scheduledTask) has finished or is not running"
                    }
                    else {
                        $allTasksFinished = $false
                    }
                }
                if (-not $allTasksFinished) {
                    Write-Output 'At least one taskg is still running. Waiting...'
                    Start-Sleep -Seconds 10
                }
            }
            Write-Output "All Scheduled Tasks have finished"
        }

        # Run SPConfigWizard on Master SharePoint Server
        try {
            Write-Output "Getting status of Configuration Wizard on server: $($env:COMPUTERNAME)"
            Start-SPSConfigExe
        }
        catch {
            # Handle errors during Run SPConfigWizard on Master SharePoint Server
            Write-Error -Message @"
Failed to Run SPConfigWizard on Master SharePoint Server
Target Server:  $($env:COMPUTERNAME)
Target SPFarm: $($spFarmName)
Exception: $_
"@
        }


        # Run SPConfigWizard on other SharePoint Server
        $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
        foreach ($server in $spServers) {
            try {
                $spTargetServer = "$($server.Name).$($scriptFQDN)"
                Write-Output "Getting status of Configuration Wizard on server: $($server.Name)"
                Start-SPSConfigExeRemote -Server $spTargetServer -InstallAccount $ADM
            }
            catch {
                # Handle errors during Run SPConfigWizard on remote SharePoint Server
                Write-Error -Message @"
Failed to Run SPConfigWizard on Remote SharePoint Server
Target Server:  $($spTargetServer)
Target SPFarm: $($spFarmName)
Exception: $_
"@
            }
        }

        # Enable SideBySideToken and run Copy-SPSideBySideFiles on master server
        if (-not([string]::IsNullOrEmpty($jsonEnvCfg.SideBySideToken.BuildVersion))) {
            try {
                Write-Output "Configuring SharePoint SideBySideToken on farm $($spFarmName)"
                Set-SPSSideBySideToken -BuildVersion "$($jsonEnvCfg.SideBySideToken.BuildVersion)" -EnableSideBySide $jsonEnvCfg.SideBySideToken.Enable
            }
            catch {
                # Handle errors during Run Set-SPSSideBySideToken
                Write-Error -Message @"
Failed to Run Set-SPSSideBySideToken CmdLet
Target SPFarm: $($spFarmName)
Exception: $_
"@
            }
        }

        # Run Copy-SPSideBySideFiles on other servers
        if ($jsonEnvCfg.SideBySideToken.Enable) {
            $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
            foreach ($server in $spServers) {
                try {
                    $spTargetServer = "$($server.Name).$($scriptFQDN)"
                    Copy-SPSSideBySideFilesAllServers -Server $spTargetServer -InstallAccount $ADM
                }
                catch {
                    # Handle errors during Run Copy-SPSSideBySideFilesAllServers
                    Write-Error -Message @"
Failed to Run Copy-SPSideBySideFiles CmdLet
Target Server:  $($spTargetServer)
Target SPFarm: $($spFarmName)
Exception: $_
"@
                }
            }            
        }
    }
}
#endregion

# Clean-Up
Trap { Continue }
$DateEnded = Get-Date
Write-Output '-----------------------------------------------'
Write-Output "| SPSUpdate Script Completed"
Write-Output "| Started on  - $DateStarted"
Write-Output "| Ended on    - $DateEnded"
Write-Output '-----------------------------------------------'
Stop-Transcript
Remove-Variable * -ErrorAction SilentlyContinue
Remove-Module * -ErrorAction SilentlyContinue
$error.Clear()
Exit
