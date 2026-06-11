<#
    .SYNOPSIS
    SPSUpdate script for SharePoint Server.

    .DESCRIPTION
    SPSUpdate is a PowerShell script tool designed to install cumulative updates in your SharePoint environment.
    It's compatible with PowerShell version 5.1 and later.

    .PARAMETER ConfigFile
    Need parameter ConfigFile, example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'E:\SCRIPT\CONFIG\contoso-PROD.json'

    .PARAMETER Action
    Use the Action parameter equal to Install if you want to add the SPSUpdate script in taskscheduler
    InstallAccount parameter need to be set
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential)

    Use the Action parameter equal to Uninstall if you want to remove the SPSUpdate script from taskscheduler
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Uninstall

    Use the Action parameter equal to ProductUpdate if you want to run the ProductUpdate locally
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'contoso-PROD.json'

    Use the Action parameter equal to InitContentDB if you want to (re)generate the ContentDatabase JSON
    inventory file used to prepare a farm upgrade (for example SharePoint 2019 to Subscription Edition).
    This action runs Initialize-SPSContentDbJsonFile against the local farm and overwrites the existing
    inventory file so that it always reflects the current state of the source farm.
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'contoso-PROD.json'

    .PARAMETER Sequence
    Need parameter Sequence for SPS Farm, example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Sequence 1

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use the Action Install parameter
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'

    .EXAMPLE
    SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'
    SPSUpdate.ps1 -Action Uninstall -ConfigFile 'contoso-PROD.json'
    SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'contoso-PROD.json'
    SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'contoso-PROD.json'

    .NOTES
    FileName:	SPSUpdate.ps1
    Author:		Jean-Cyril DROUHIN
    Date:		June 11, 2026
    Version:	3.2.1

    .LINK
    https://spjc.fr/
    https://github.com/luigilink/SPSUpdate
#>
[CmdletBinding()]
param
(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateScript({ (Test-Path $_) -and ($_ -like '*.json') })]
    [System.String]
    $ConfigFile, # Path to the configuration file

    [Parameter(Position = 1)]
    [validateSet('Install', 'Uninstall', 'Default', 'ProductUpdate', 'InitContentDB', IgnoreCase = $true)]
    [System.String]
    $Action = 'Default',

    [Parameter(Position = 2)]
    [ValidateRange(1, 4)]
    [System.UInt32]
    $Sequence,

    [Parameter(Position = 3)]
    [System.Management.Automation.PSCredential]
    $InstallAccount # Credential for the InstallAccount (when Action is Install)
)

#region Initialization
# When the script is invoked with -Verbose, forward that preference to all downstream commands
# that support the common Verbose parameter, including imported module functions.
if ($PSBoundParameters.ContainsKey('Verbose')) {
    $PSDefaultParameterValues['*:Verbose'] = $true
}

# Clear the host console
Clear-Host

# Define the path to the helper module
$script:HelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules'

# Import the helper module
try {
    Import-Module -Name (Join-Path -Path $script:HelperModulePath -ChildPath 'util.psm1') -Force
}
catch {
    # Handle errors during Import of helper module
    Write-Error -Message @"
Failed to import helper module from path: $($script:HelperModulePath)
Exception: $_
"@
    Exit
}


# Import the credentialmanager module
try {
    Import-Module -Name (Join-Path -Path (Join-Path -Path $script:HelperModulePath -ChildPath 'credentialmanager') -ChildPath 'CredentialManager.psd1') -Force
}
catch {
    # Handle errors during Import of credentialmanager module
    Write-Error -Message @"
Failed to import credentialmanager module from path: $(Join-Path -Path $script:HelperModulePath -ChildPath 'credentialmanager')
Exception: $_
"@
    Exit
}

# Ensure the script is running with administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Throw "Administrator rights are required. Please re-run this script as an Administrator."
}

# Define task name constants
$script:TaskNameFullScript = 'SPSUpdate-FullScript'
$script:TaskNameSequencePrefix = 'SPSUpdate-Sequence'
$script:TaskPath = 'SharePoint'

# Function to validate configuration file
function Test-ConfigurationFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFilePath,
        
        [Parameter(Mandatory = $true)]
        [ref]
        $ConfigObject
    )
    
    $requiredProperties = @('ApplicationName', 'ConfigurationName', 'Domain', 'FarmName', 'StoredCredential')
    
    # Check if file exists and is readable
    if (-not (Test-Path $ConfigFilePath -PathType Leaf)) {
        throw "Configuration file not found or not accessible: $ConfigFilePath"
    }
    
    # Parse JSON
    try {
        $config = Get-Content $ConfigFilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Configuration file is not valid JSON: $_"
    }
    
    # Validate required properties
    foreach ($property in $requiredProperties) {
        if (-not ($config | Get-Member -Name $property -MemberType NoteProperty)) {
            throw "Configuration file is missing required property: $property"
        }
        if ([string]::IsNullOrWhiteSpace($config.$property)) {
            throw "Configuration property '$property' cannot be empty"
        }
    }
    
    $ConfigObject.Value = $config
    return $true
}

# Load and validate the configuration file
try {
    $configRef = $null
    if (Test-ConfigurationFile -ConfigFilePath $ConfigFile -ConfigObject ([ref]$configRef)) {
        $jsonEnvCfg = $configRef
        $Application = $jsonEnvCfg.ApplicationName
        $Environment = $jsonEnvCfg.ConfigurationName
        $scriptFQDN = $jsonEnvCfg.Domain
        $spFarmName = $jsonEnvCfg.FarmName
        Write-Verbose "Configuration file validated successfully: $ConfigFile"
    }
}
catch {
    Write-Error "Failed to load configuration file: $_"
    Exit
}

# Define variables
$SPSUpdateVersion = '3.2.1'
$getDateFormatted = Get-Date -Format yyyy-MM-dd_H-mm
$spsUpdateFileName = "$($Application)-$($Environment)_$($getDateFormatted)"
$spsUpdateDBsFile = "$($Application)-$($Environment)-$($spFarmName)-ContentDBs.json"
$currentUser = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
$pathLogsFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Logs'
$pathConfigFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Config'
$fullScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'SPSUpdate.ps1'
$spsUpdateDBsPath = Join-Path -Path $pathConfigFolder -ChildPath $spsUpdateDBsFile

# Initialize logs
if (-Not (Test-Path -Path $pathLogsFolder)) {
    New-Item -ItemType Directory -Path $pathLogsFolder -Force
}
if ($PSBoundParameters.ContainsKey('Sequence')) {
    $pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ("$($Application)-$($Environment)_Sequence$($Sequence)_" + (Get-Date -Format yyyy-MM-dd_H-mm) + '.log')
}
elseif ($PSBoundParameters.ContainsKey('Action') -and $Action -eq 'ProductUpdate') {
    $pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ("$($Application)-$($Environment)_ProductUpdate-$($env:COMPUTERNAME)_" + (Get-Date -Format yyyy-MM-dd_H-mm) + '.log')
}
elseif ($PSBoundParameters.ContainsKey('Action') -and $Action -eq 'InitContentDB') {
    $pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ("$($Application)-$($Environment)_InitContentDB-$($env:COMPUTERNAME)_" + (Get-Date -Format yyyy-MM-dd_H-mm) + '.log')
}
else {
    $pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ($spsUpdateFileName + '.log')
}
$DateStarted = Get-Date
$psVersion = $PSVersionTable.PSVersion.ToString()
$script:TranscriptStarted = $false

# Start transcript to log the output
try {
    Start-Transcript -Path $pathLogFile -IncludeInvocationHeader -ErrorAction Stop
    $script:TranscriptStarted = $true
    Write-Output "Transcript log file: $pathLogFile"
}
catch {
    Write-Warning "Unable to start transcript: $($_.Exception.Message)"
    Write-Output "Transcript disabled for this run. Intended log file path: $pathLogFile"
}

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
    Write-Output "Installed SharePoint Product Version: $($installedVersion.FileVersion)"
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
    $catchMessage = @"
Failed to get installed Product Version for $($env:COMPUTERNAME)
Exception: $_
"@
    Write-Error -Message $catchMessage    
    Add-SPSUpdateEvent -Message $catchMessage -Source 'Get-SPSInstalledProductVersion' -EntryType 'Error'
}

# 2. Initialize or read ContentDatabase json file if UpgradeContentDatabase or MountContentDatabase equal to true
try {
    if ($jsonEnvCfg.UpgradeContentDatabase -or $jsonEnvCfg.MountContentDatabase) {
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
    $catchMessage = @"
Failed to Initialize ContentDatabase json file for SPFARM: $($spFarmName)
Exception: $_
"@
    Write-Error -Message $catchMessage    
    Add-SPSUpdateEvent -Message $catchMessage -Source 'Initialize-SPSContentDbJsonFile' -EntryType 'Error'
}

# 3. Execute Action parameter
switch ($Action) {
    'InitContentDB' {
        # (Re)generate the ContentDatabase inventory JSON file for the local farm.
        # Typically used on a source farm (for example SP2019) to prepare an upgrade
        # to a target farm (for example Subscription Edition) where the file will
        # later be consumed by the MountContentDatabase flow.
        try {
            if (-Not (Test-Path -Path $pathConfigFolder)) {
                New-Item -ItemType Directory -Path $pathConfigFolder -Force | Out-Null
            }
            Write-Output "Initializing ContentDatabase json file for SPFARM: $($spFarmName)"
            Write-Output "Target file: $spsUpdateDBsPath"
            Initialize-SPSContentDbJsonFile -Path $spsUpdateDBsPath
            if (Test-Path -Path $spsUpdateDBsPath) {
                Write-Output "ContentDatabase json file generated successfully: $spsUpdateDBsPath"
            }
            else {
                throw "ContentDatabase json file was not created: $spsUpdateDBsPath"
            }
        }
        catch {
            $catchMessage = @"
Failed to (re)Initialize ContentDatabase json file for SPFARM: $($spFarmName)
Exception: $_
"@
            Write-Error -Message $catchMessage
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Initialize-SPSContentDbJsonFile' -EntryType 'Error'
            if ($script:TranscriptStarted) {
                Stop-Transcript | Out-Null
                $script:TranscriptStarted = $false
            }
            exit
        }
    }
    'Uninstall' {
        # Remove scheduled Task for Update Full Script
        try {
            Write-Output "Removing Scheduled Task $script:TaskNameFullScript in $script:TaskPath Task Path"
            Remove-SPSScheduledTask -Name $script:TaskNameFullScript -TaskPath $script:TaskPath
        }
        catch {
            # Handle errors during Remove scheduled Task for Update Full Script
            $catchMessage = @"
Failed to Remove Scheduled Task $script:TaskNameFullScript in $script:TaskPath Task Path
Exception: $_
"@
            Write-Error -Message $catchMessage    
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Remove-SPSScheduledTask' -EntryType 'Error'
        }
        # Remove scheduled Task for Upgrade SPContentDatabase in Parallel
        try {
            foreach ($taskId in (1..4)) {
                $taskName = "$script:TaskNameSequencePrefix$taskId"
                Write-Output "Removing Scheduled Tasks $taskName in $script:TaskPath Task Path"
                Remove-SPSScheduledTask -Name $taskName -TaskPath $script:TaskPath
            }
        }
        catch {
            $catchMessage = @"
Failed to Remove Scheduled Task $script:TaskNameSequencePrefix$taskId in $script:TaskPath Task Path
Exception: $_
"@
            Write-Error -Message $catchMessage    
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Remove-SPSScheduledTask' -EntryType 'Error'
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
            $catchMessage = @"
Failed to Get or Remove Credential in Crededential Manager for SPFarm: $($spFarmName)
Exception: $_
"@
            Write-Error -Message $catchMessage    
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Remove-StoredCredential' -EntryType 'Error'
        }
    }
    'Install' {
        # Check UserName and Password if Install parameter is used
        if (-not($PSBoundParameters.ContainsKey('InstallAccount'))) {
            Write-Warning -Message ('SPSUpdate: Install parameter is set. Please set also InstallAccount ' + `
                    "parameter. `nSee https://github.com/luigilink/SPSUpdate/wiki for details.")
            exit
        }
        else {
            $UserName = $InstallAccount.UserName
            $Password = $InstallAccount.GetNetworkCredential().Password
            $currentDomain = 'LDAP://' + ([ADSI]'').distinguishedName
            Write-Output "Checking Account `"$UserName`" ..."
            $dom = New-Object System.DirectoryServices.DirectoryEntry($currentDomain, $UserName, $Password)
            if ($null -eq $dom.Path) {
                Write-Warning -Message "Password Invalid for user:`"$UserName`""
                exit
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
                    $catchMessage = @"
Failed to Get or Add Credential in Crededential Manager for SPFarm: $($spFarmName)
Exception: $_
"@
                    Write-Error -Message $catchMessage    
                    Add-SPSUpdateEvent -Message $catchMessage -Source 'New-StoredCredential' -EntryType 'Error'
                }
            }
            # Add scheduled Task for Update Full Script
            try {
                # Initialize ActionArguments parameter
                $ActionArguments = "-ExecutionPolicy Bypass -File `"$($fullScriptPath)`" -ConfigFile `"$($ConfigFile)`" -Verbose"
                Write-Output "Adding Scheduled Task $script:TaskNameFullScript in $script:TaskPath Task Path"
                    
                # Check if task already exists
                $existingTask = Get-ScheduledTask -TaskName $script:TaskNameFullScript -TaskPath "\$script:TaskPath\" -ErrorAction SilentlyContinue
                if ($null -ne $existingTask) {
                    Write-Warning "Scheduled task '$script:TaskNameFullScript' already exists. Removing and recreating..."
                    Remove-SPSScheduledTask -Name $script:TaskNameFullScript -TaskPath $script:TaskPath
                }
                    
                Add-SPSScheduledTask -Name $script:TaskNameFullScript `
                    -Description 'Scheduled Task for Update SharePoint Server after installation of cumulative update' `
                    -ActionArguments $ActionArguments `
                    -ExecuteAsCredential $InstallAccount `
                    -TaskPath $script:TaskPath
            }
            catch {
                # Handle errors during Add scheduled Task for Update Full Script
                $catchMessage = @"
Failed to Add Scheduled Task in SharePoint Task Path for SPFarm: $($spFarmName)
Exception: $_
"@
                Write-Error -Message $catchMessage    
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Add-SPSScheduledTask' -EntryType 'Error'
            }
            # Add scheduled Task for Upgrade SPContentDatabase if UpgradeContentDatabase or MountContentDatabase equal to true
            if ($jsonEnvCfg.UpgradeContentDatabase -or $jsonEnvCfg.MountContentDatabase) {
                # Get credential from Credential Manager
                $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
                if ($null -eq $credential) {
                    $credential = $InstallAccount
                }
                # Add scheduled Task for Upgrade SPContentDatabase in Parallel
                foreach ($taskId in (1..4)) {
                    try {
                        $taskName = "$script:TaskNameSequencePrefix$taskId"
                        # Initialize ActionArguments parameter
                        $ActionArguments = "-ExecutionPolicy Bypass -File `"$($fullScriptPath)`" -ConfigFile `"$($ConfigFile)`" -Sequence $taskId -Verbose"
                        Write-Output "Adding Scheduled Task $taskName in $script:TaskPath Task Path"
                            
                        # Check if task already exists
                        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath "\$script:TaskPath\" -ErrorAction SilentlyContinue
                        if ($null -ne $existingTask) {
                            Write-Warning "Scheduled task '$taskName' already exists. Removing and recreating..."
                            Remove-SPSScheduledTask -Name $taskName -TaskPath $script:TaskPath
                        }
                            
                        Add-SPSScheduledTask -Name $taskName `
                            -Description "Scheduled Task Sequence$taskId for Update SharePoint Server after installation of cumulative update" `
                            -ActionArguments $ActionArguments `
                            -ExecuteAsCredential $credential `
                            -TaskPath $script:TaskPath
                    }
                    catch {
                        # Handle errors during Add scheduled Task for Update Full Script
                        $catchMessage = @"
Failed to Add Scheduled Task in $script:TaskPath Task Path
Task Name: $taskName
Target SPFarm: $($spFarmName)
Exception: $_
"@
                        Write-Error -Message $catchMessage # Handle any errors during task removal
                        Add-SPSUpdateEvent -Message $catchMessage -Source 'Add-SPSScheduledTask' -EntryType 'Error'
                        if ($script:TranscriptStarted) {
                            Stop-Transcript | Out-Null
                            $script:TranscriptStarted = $false
                        }
                        exit
                    }
                }
            }
        }
    }
    'ProductUpdate' {
        # Run ProductUpdate
        try {
            foreach ($setupFile in $jsonEnvCfg.Binaries.SetupFileName) {
                $fullSetupFilePath = Join-Path -Path $jsonEnvCfg.Binaries.SetupFullPath -ChildPath $setupFile
                $spTargetServer = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName).ToString()
                Write-Output @"
Running ProductUpdate with following parameters:
SharePoint Server: $($spTargetServer)
Setup File Path: $($fullSetupFilePath)
Shutdown Services: $($jsonEnvCfg.Binaries.ShutdownServices)
"@
                # NOTE: Pending reboot detection was removed because on production farms the
                # Windows reboot markers (CBS, PendingFileRenameOperations, etc.) commonly
                # remain set after several reboots, which caused the script to abort the
                # ProductUpdate even when the system was actually in a healthy state.
                # Unblock setup file if it is blocked
                Unblock-File -Path $fullSetupFilePath -Verbose
                Start-SPSProductUpdate -SetupFile $fullSetupFilePath -ShutdownServices $jsonEnvCfg.Binaries.ShutdownServices -Verbose
            }
        }
        catch {
            # Handle errors during Run ProductUpdate
            $catchMessage = @"
Failed to run ProductUpdate on server: $($env:COMPUTERNAME)
Target Server:  $($spTargetServer)
Exception: $_
"@
            Write-Error -Message $catchMessage
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSProductUpdate' -EntryType 'Error'
            if ($script:TranscriptStarted) {
                Stop-Transcript | Out-Null
                $script:TranscriptStarted = $false
            }
            exit
        }
    }
    Default {
        if ($PSBoundParameters.ContainsKey('Sequence')) {
            try {
                Write-Output "Update Script in progress | Sequence $Sequence  - Please Wait ..."
                switch ($Sequence) {
                    1 { $dbs = $jsonDbCfg.SPContentDatabase1 }
                    2 { $dbs = $jsonDbCfg.SPContentDatabase2 }
                    3 { $dbs = $jsonDbCfg.SPContentDatabase3 }
                    4 { $dbs = $jsonDbCfg.SPContentDatabase4 }
                }
                foreach ($db in $dbs) {
                    # Mount SPContentDatabase (typically used to attach databases coming from a
                    # previous farm version, for example SP2019 -> Subscription Edition migration).
                    # Mounts run inside each Sequence scheduled task, so the 4 sequences process
                    # their respective DB groups in parallel. Each database list is loaded from
                    # the ContentDatabase inventory JSON file produced by Initialize-SPSContentDbJsonFile.
                    # Mount and Upgrade are independent: a farm can be configured for Mount only,
                    # Upgrade only, or both (Mount then Upgrade for SP2019 -> SE migration).
                    if ($jsonEnvCfg.MountContentDatabase) {
                        try {
                            Mount-SPSContentDatabase -Name $db.Name -WebAppUrl $db.WebAppUrl -DatabaseServer $db.Server
                        }
                        catch {
                            $catchMessage = @"
Failed to Mount SPContentDatabase '$($db.Name)' on WebApplication '$($db.WebAppUrl)'
Target SPFarm: $($spFarmName)
Exception: $_
"@
                            Write-Error -Message $catchMessage
                            Add-SPSUpdateEvent -Message $catchMessage -Source 'Mount-SPSContentDatabase' -EntryType 'Error'
                        }
                    }
                    if ($jsonEnvCfg.UpgradeContentDatabase) {
                        Update-SPSContentDatabase -Name $db.Name
                    }
                }
            }
            catch {
                # Handle errors during Update Script Sequence
                $catchMessage = @"
Failed to Upgrade SPContentDatabse '$($db.Name)' during sequence: $($Sequence)
Target SPFarm: $($spFarmName)
Exception: $_
"@
                Write-Error -Message $catchMessage
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Update-SPSContentDatabase' -EntryType 'Error'
            }
        }
        else {
            # Initialize Security
            try {
                $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)"
            }
            catch {
                # Handle errors during Update Script Sequence
                $catchMessage = @"
Failed to initialize Security from Crededential Manager
The Target $($jsonEnvCfg.StoredCredential) not present in Credential Manager
Please review your configuration file or contact your administrator.
Exception: $_
"@
                Write-Error -Message $catchMessage
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Get-StoredCredential' -EntryType 'Error'
                if ($script:TranscriptStarted) {
                    Stop-Transcript | Out-Null
                    $script:TranscriptStarted = $false
                }
                exit
            }
            Write-Output "Update Script in progress | FULL Mode - Please Wait ..."
            # Mount and/or Upgrade SPContentDatabase via parallel scheduled tasks.
            # The sequence tasks themselves decide what to do for each database based on
            # the MountContentDatabase and UpgradeContentDatabase flags in the JSON config.
            if ($jsonEnvCfg.UpgradeContentDatabase -or $jsonEnvCfg.MountContentDatabase) {
                # Add scheduled Task for Upgrade SPContentDatabase in Parallel
                foreach ($taskId in (1..4)) {
                    try {
                        # Initialize ActionArguments parameter
                        $ActionArguments = "-ExecutionPolicy Bypass -File `"$($fullScriptPath)`" -ConfigFile `"$($ConfigFile)`" -Sequence $taskId -Verbose"
                        $taskName = "$script:TaskNameSequencePrefix$taskId"
                        Write-Output "Adding Scheduled Task $taskName in $script:TaskPath Task Path"
                        
                        # Check if task already exists
                        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath "\$script:TaskPath\" -ErrorAction SilentlyContinue
                        if ($null -ne $existingTask) {
                            Write-Warning "Scheduled task '$taskName' already exists. Removing and recreating..."
                            Remove-SPSScheduledTask -Name $taskName -TaskPath $script:TaskPath
                        }
                        
                        Add-SPSScheduledTask -Name $taskName `
                            -Description "Scheduled Task Sequence$taskId for Update SharePoint Server after installation of cumulative update" `
                            -ActionArguments $ActionArguments `
                            -ExecuteAsCredential $credential `
                            -TaskPath $script:TaskPath
                    }
                    catch {
                        # Handle errors during Add scheduled Task for Update Full Script
                        $catchMessage = @"
Failed to Add Scheduled Task in $script:TaskPath Task Path
Task Name: $taskName
Target SPFarm: $($spFarmName)
Exception: $_
"@
                        Write-Error -Message $catchMessage
                        Add-SPSUpdateEvent -Message $catchMessage -Source 'Add-SPSScheduledTask' -EntryType 'Error'
                        if ($script:TranscriptStarted) {
                            Stop-Transcript | Out-Null
                            $script:TranscriptStarted = $false
                        }
                        exit
                    }
                }

                # Run scheduled Task for Upgrade SPContentDatabase in Parallel
                foreach ($taskId in (1..4)) {
                    try {
                        $taskName = "$script:TaskNameSequencePrefix$taskId"
                        Write-Output "Running Scheduled Task $taskName in $script:TaskPath Task Path"
                        $startResult = Start-SPSScheduledTask -Name $taskName -TaskPath $script:TaskPath -ErrorAction Stop
                        Write-Output "Start requested for $($startResult.Name) in $($startResult.TaskPath). Current state: $($startResult.State)"
                        Write-Output 'Avoid conflicts with OWSTimer process - Pause between 60 to 90 seconds'
                        Start-Sleep -Seconds (get-random (60..90))
                    }
                    catch {
                        # Handle errors during Start scheduled Task for Upgrade SPContentDatabase in Parallel
                        $catchMessage = @"
Failed to Start Scheduled Task in $script:TaskPath Task Path
Task Name: $taskName
Target SPFarm: $($spFarmName)
Exception: $_
"@
                        Write-Error -Message $catchMessage
                        Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSScheduledTask' -EntryType 'Error'
                    }
                }

                # Wait until all scheduled Tasks are finished
                # Define list variable of scheduled tasks
                $scheduledTasks = @(
                    "$script:TaskNameSequencePrefix`1",
                    "$script:TaskNameSequencePrefix`2",
                    "$script:TaskNameSequencePrefix`3",
                    "$script:TaskNameSequencePrefix`4"
                )

                # Continuously check the status of tasks until all are finished
                $allTasksFinished = $false
                while (-not $allTasksFinished) {
                    $allTasksFinished = $true
                    foreach ($scheduledTask in $scheduledTasks) {
                        $taskStatus = Get-ScheduledTask -TaskName $scheduledTask -TaskPath "\$script:TaskPath\" -ErrorAction SilentlyContinue
                        if ($null -eq $taskStatus) {
                            Write-Warning "Scheduled Task $scheduledTask was not found in $script:TaskPath Task Path"
                            continue
                        }
                        if ($taskStatus.State -ne 'Running' -and $taskStatus.State -ne 'Queued') {
                            Write-Output "Scheduled Task $($scheduledTask) has finished or is not running"
                        }
                        else {
                            $allTasksFinished = $false
                        }
                    }
                    if (-not $allTasksFinished) {
                        Write-Output 'At least one task is still running. Waiting...'
                        Start-Sleep -Seconds 10
                    }
                }
                Write-Output "All Scheduled Tasks have finished"
            }

            # Run Configuration Wizard on Master SharePoint Server
            try {
                # Get patch status on Master SharePoint Server
                Write-Output "Getting Patch Status on server: $($env:COMPUTERNAME)"
                if ((Get-SPSServersPatchStatus -Server "$($env:COMPUTERNAME)") -eq 'NoActionRequired') {
                    Write-Output "No Action Required on server: $($env:COMPUTERNAME). Skipping Configuration Wizard."
                }
                else {
                    Write-Output "Action Required on server: $($env:COMPUTERNAME). Proceeding to run Configuration Wizard."
                    Start-SPSConfigExe
                }
            }
            catch {
                # Handle errors during Run SPConfigWizard on Master SharePoint Server
                $catchMessage = @"
Failed to Run SPConfigWizard on Master SharePoint Server
Target Server:  $($env:COMPUTERNAME)
Target SPFarm: $($spFarmName)
Exception: $_
"@
                Write-Error -Message $catchMessage
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSConfigExe' -EntryType 'Error'
            }

            # Run SPConfigWizard on other SharePoint Server
            $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
            foreach ($spServer in $spServers) {
                try {
                    # Get patch status on Master SharePoint Server
                    Write-Output "Getting Patch Status on server: $($spServer.Name)"
                    if ((Get-SPSServersPatchStatus -Server "$($spServer.Name)") -eq 'NoActionRequired') {
                        Write-Output "No Action Required on server: $($spServer.Name). Skipping Configuration Wizard."
                    }
                    else {
                        Write-Output "Action Required on server: $($spServer.Name). Proceeding to run Configuration Wizard."
                        $spTargetServer = "$($spServer.Name).$($scriptFQDN)"
                        Start-SPSConfigExeRemote -Server $spTargetServer -InstallAccount $credential
                    }
                }
                catch {
                    # Handle errors during Run SPConfigWizard on remote SharePoint Server
                    $catchMessage = @"
Failed to Run SPConfigWizard on Remote SharePoint Server
Target Server:  $($spTargetServer)
Target SPFarm: $($spFarmName)
Exception: $_
"@
                    Write-Error -Message $catchMessage
                    Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSConfigExeRemote' -EntryType 'Error'
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
                    $catchMessage = @"
Failed to Run Set-SPSSideBySideToken CmdLet
Target SPFarm: $($spFarmName)
Exception: $_
"@
                    Write-Error -Message $catchMessage
                    Add-SPSUpdateEvent -Message $catchMessage -Source 'Set-SPSSideBySideToken' -EntryType 'Error'
                }
            }

            # Run Copy-SPSideBySideFiles on other servers
            if ($jsonEnvCfg.SideBySideToken.Enable) {
                $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
                foreach ($spServer in $spServers) {
                    try {
                        $spTargetServer = "$($spServer.Name).$($scriptFQDN)"
                        Copy-SPSSideBySideFilesRemote -Server $spTargetServer -InstallAccount $credential
                    }
                    catch {
                        # Handle errors during Run Copy-SPSSideBySideFilesAllServers
                        $catchMessage = @"
Failed to Run Copy-SPSideBySideFiles CmdLet
Target Server:  $($spTargetServer)
Target SPFarm: $($spFarmName)
Exception: $_
"@
                        Write-Error -Message $catchMessage
                        Add-SPSUpdateEvent -Message $catchMessage -Source 'Copy-SPSSideBySideFiles' -EntryType 'Error'
                    }
                }
            }
        }
    }
}
#endregion

# Clean-Up
$DateEnded = Get-Date
Write-Output '-----------------------------------------------'
Write-Output "| SPSUpdate Script Completed"
Write-Output "| Started on  - $DateStarted"
Write-Output "| Ended on    - $DateEnded"
Write-Output '-----------------------------------------------'
if ($script:TranscriptStarted) {
    Stop-Transcript | Out-Null
    $script:TranscriptStarted = $false
}
$loadedModules = @('util', 'CredentialManager')
$loadedModules | ForEach-Object { Remove-Module -Name $_ -ErrorAction SilentlyContinue }
$error.Clear()
Exit
