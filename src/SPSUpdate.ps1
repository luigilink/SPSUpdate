<#
    .SYNOPSIS
    SPSUpdate script for SharePoint Server.

    .DESCRIPTION
    SPSUpdate is a PowerShell script tool designed to install cumulative updates in your SharePoint environment.
    It's compatible with PowerShell version 5.1 and later.

    Shared logic lives in the SPSUpdate.Common module (src/Modules/SPSUpdate.Common). The
    environment configuration is a PowerShell data file (*.psd1) and the InstallAccount
    credential is stored as a DPAPI-encrypted SecureString in Config\secrets.psd1 (there
    is no longer any dependency on the Windows Credential Manager module).

    .PARAMETER ConfigFile
    Path to the environment configuration file (*.psd1), example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'E:\SCRIPT\CONFIG\CONTOSO-PROD-CONTENT.psd1'

    .PARAMETER Action
    Use the Action parameter equal to Install if you want to add the SPSUpdate script in taskscheduler.
    InstallAccount parameter needs to be set.
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    Use the Action parameter equal to Uninstall if you want to remove the SPSUpdate script from taskscheduler.
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Uninstall -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    Use the Action parameter equal to ProductUpdate if you want to run the ProductUpdate locally.
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    Use the Action parameter equal to InitContentDB if you want to (re)generate the ContentDatabase JSON
    inventory file used to prepare a farm upgrade (for example SharePoint 2019 to Subscription Edition).
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    .PARAMETER Sequence
    Need parameter Sequence for SPS Farm, example:
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Sequence 1

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use the Action Install parameter
    PS D:\> E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    .EXAMPLE
    SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
    SPSUpdate.ps1 -Action Uninstall -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
    SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
    SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'

    .NOTES
    FileName:	SPSUpdate.ps1
    Author:		Jean-Cyril DROUHIN
    Date:		June 29, 2026
    Version:	Defined by the SPSUpdate.Common module manifest (ModuleVersion)

    .LINK
    https://spjc.fr/
    https://github.com/luigilink/SPSUpdate
#>
[CmdletBinding()]
param
(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateScript({ (Test-Path $_) -and ($_ -like '*.psd1') })]
    [System.String]
    $ConfigFile, # Path to the configuration file

    [Parameter(Position = 1)]
    [validateSet('Install', 'Uninstall', 'Default', 'ProductUpdate', 'InitContentDB', 'ResetStatus', IgnoreCase = $true)]
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
$Host.UI.RawUI.WindowTitle = "SPSUpdate script running on $env:COMPUTERNAME"

# Import the helper module (SPSUpdate.Common)
$script:HelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules'
try {
    Import-Module -Name (Join-Path -Path $script:HelperModulePath -ChildPath 'SPSUpdate.Common\SPSUpdate.Common.psd1') -Force -ErrorAction Stop
}
catch {
    Write-Error -Message @"
Failed to import SPSUpdate.Common module from path: $($script:HelperModulePath)
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

# Function to load, validate and normalize the psd1 configuration file.
# Required keys raise a clear error; optional behaviour keys fall back to safe defaults.
function Get-SPSUpdateConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFilePath
    )

    if (-not (Test-Path $ConfigFilePath -PathType Leaf)) {
        throw "Configuration file not found or not accessible: $ConfigFilePath"
    }

    try {
        $config = Import-PowerShellDataFile -Path $ConfigFilePath -ErrorAction Stop
    }
    catch {
        throw "Configuration file is not a valid PowerShell data file (psd1): $_"
    }

    # Validate required top-level properties
    $requiredProperties = @('ApplicationName', 'ConfigurationName', 'Domain', 'FarmName', 'CredentialKey')
    foreach ($property in $requiredProperties) {
        if (-not $config.ContainsKey($property)) {
            throw "Configuration file is missing required property: $property"
        }
        if ([string]::IsNullOrWhiteSpace([string]$config[$property])) {
            throw "Configuration property '$property' cannot be empty"
        }
    }

    # Normalize the Binaries block and apply defaults
    if (-not $config.ContainsKey('Binaries') -or $null -eq $config.Binaries) {
        $config.Binaries = @{}
    }
    if (-not $config.Binaries.ContainsKey('ProductUpdate')) {
        $config.Binaries.ProductUpdate = $true
    }
    if (-not $config.Binaries.ContainsKey('ShutdownServices')) {
        $config.Binaries.ShutdownServices = $true
    }

    # Apply content-database defaults
    if (-not $config.ContainsKey('MountContentDatabase')) {
        $config.MountContentDatabase = $false
    }
    if (-not $config.ContainsKey('UpgradeContentDatabase')) {
        $config.UpgradeContentDatabase = $true
    }

    # Normalize the SideBySideToken block and apply defaults
    if (-not $config.ContainsKey('SideBySideToken') -or $null -eq $config.SideBySideToken) {
        $config.SideBySideToken = @{}
    }
    if (-not $config.SideBySideToken.ContainsKey('Enable')) {
        $config.SideBySideToken.Enable = $false
    }
    if (-not $config.SideBySideToken.ContainsKey('BuildVersion')) {
        $config.SideBySideToken.BuildVersion = ''
    }

    # StatusStorePath is optional; empty string means "use the local Results\status folder".
    if (-not $config.ContainsKey('StatusStorePath') -or $null -eq $config.StatusStorePath) {
        $config.StatusStorePath = ''
    }

    return $config
}

# Load and validate the configuration file
try {
    $envCfg = Get-SPSUpdateConfiguration -ConfigFilePath $ConfigFile
    $Application = $envCfg.ApplicationName
    $Environment = $envCfg.ConfigurationName
    $scriptFQDN = $envCfg.Domain
    $spFarmName = $envCfg.FarmName
    Write-Verbose "Configuration file validated successfully: $ConfigFile"
}
catch {
    Write-Error "Failed to load configuration file: $_"
    Exit
}

# Define variables
$SPSUpdateVersion = (Get-Module -Name 'SPSUpdate.Common').Version.ToString()
$getDateFormatted = Get-Date -Format yyyy-MM-dd_H-mm
$spsUpdateFileName = "$($Application)-$($Environment)_$($getDateFormatted)"
$spsUpdateDBsFile = "$($Application)-$($Environment)-$($spFarmName)-ContentDBs.json"
$spsUpdateDbReportFile = "$($Application)-$($Environment)-$($spFarmName)-ContentDBs.html"
$currentUser = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
$pathLogsFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Logs'
$pathConfigFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Config'
$pathResultsFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Results'
$fullScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'SPSUpdate.ps1'
$spsUpdateDBsPath = Join-Path -Path $pathConfigFolder -ChildPath $spsUpdateDBsFile
$spsUpdateDbReportPath = Join-Path -Path $pathResultsFolder -ChildPath $spsUpdateDbReportFile

# Resolve the patching status store campaign folder (UNC share when configured, local
# Results\status fallback otherwise). Shared by every server/task to feed the live
# dashboard. Identity is <App>-<Env>-<Farm> so same-campaign actions land together.
$thisServer = $env:COMPUTERNAME
$statusCampaignPath = $null
try {
    $statusCampaignPath = Get-SPSStatusCampaignPath -StatusStorePath $envCfg.StatusStorePath `
        -ResultsFolder $pathResultsFolder `
        -Application $Application `
        -Environment $Environment `
        -FarmName $spFarmName
}
catch {
    Write-Warning -Message "Could not resolve the status store campaign path: $($_.Exception.Message)"
}
$statusDashboardPath = if ($null -ne $statusCampaignPath) { Join-Path -Path $statusCampaignPath -ChildPath '_dashboard.html' } else { $null }

# Local helper: best-effort status write. Never blocks the run on a status failure.
function Write-SPSStatus {
    param(
        [Parameter(Mandatory = $true)][System.String] $Scope,
        [Parameter(Mandatory = $true)][ValidateSet('ProductUpdate', 'Mount', 'Upgrade', 'Sequence', 'Wizard', 'SideBySide')][System.String] $Phase,
        [System.String] $Server = $thisServer,
        [System.String] $State,
        [System.String] $Detail,
        [System.Nullable[int]] $Percent,
        [System.String] $Item,
        [System.String] $ItemState,
        [System.String] $ItemDetail,
        [System.Nullable[int]] $ExitCode
    )
    if ([string]::IsNullOrEmpty($statusCampaignPath)) { return }
    try {
        $params = @{ CampaignPath = $statusCampaignPath; Scope = $Scope; Phase = $Phase; Server = $Server; Confirm = $false }
        if ($PSBoundParameters.ContainsKey('State')) { $params.State = $State }
        if ($PSBoundParameters.ContainsKey('Detail')) { $params.Detail = $Detail }
        if ($PSBoundParameters.ContainsKey('Percent') -and $null -ne $Percent) { $params.Percent = $Percent }
        if ($PSBoundParameters.ContainsKey('Item')) { $params.Item = $Item }
        if ($PSBoundParameters.ContainsKey('ItemState')) { $params.ItemState = $ItemState }
        if ($PSBoundParameters.ContainsKey('ItemDetail')) { $params.ItemDetail = $ItemDetail }
        if ($PSBoundParameters.ContainsKey('ExitCode') -and $null -ne $ExitCode) { $params.ExitCode = $ExitCode }
        $null = Set-SPSUpdateStatus @params
    }
    catch {
        Write-Warning -Message "Failed to write patching status ($Scope): $($_.Exception.Message)"
    }
}

# Local helper: (re)generate the live dashboard from the status store.
function Write-SPSDashboard {
    param([switch] $Completed)
    if ([string]::IsNullOrEmpty($statusCampaignPath)) { return }
    try {
        $params = @{
            CampaignPath = $statusCampaignPath
            OutputFile   = $statusDashboardPath
            EnvName      = $Environment
            AppCode      = $Application
            FarmName     = $spFarmName
        }
        if ($Completed) { $params.Completed = $true }
        $null = Export-SPSUpdateProgressReport @params
    }
    catch {
        Write-Warning -Message "Failed to generate patching dashboard: $($_.Exception.Message)"
    }
}

# Local helper: (re)generate the ContentDatabase inventory HTML report from the JSON
# inventory, into the Results folder. Never blocks the run on a report failure.
function Write-SPSUpdateDbReport {
    param(
        [Parameter(Mandatory = $true)][System.String] $JsonPath,
        [Parameter(Mandatory = $true)][System.String] $ReportPath
    )
    try {
        if (-not (Test-Path -Path $JsonPath)) {
            return
        }
        if (-not (Test-Path -Path $pathResultsFolder)) {
            New-Item -ItemType Directory -Path $pathResultsFolder -Force | Out-Null
        }
        $null = Export-SPSUpdateDbReport -InputFile $JsonPath `
            -OutputFile $ReportPath `
            -EnvName $Environment `
            -AppCode $Application `
            -FarmName $spFarmName
        Write-Output "ContentDatabase inventory report generated: $ReportPath"
    }
    catch {
        Write-Warning -Message "Failed to generate ContentDatabase inventory report: $($_.Exception.Message)"
    }
}

# Initialize logs
if (-Not (Test-Path -Path $pathLogsFolder)) {
    New-Item -ItemType Directory -Path $pathLogsFolder -Force | Out-Null
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

# 2. For the Default action only (full run on the master + each -Sequence sub-run),
# read or prime the ContentDatabase inventory JSON used by the mount/upgrade sequences.
# ProductUpdate/Install/Uninstall never touch the inventory; InitContentDB regenerates it
# in its own action block below.
try {
    if ($Action -eq 'Default' -and ($envCfg.UpgradeContentDatabase -or $envCfg.MountContentDatabase)) {
        if (-Not (Test-Path -Path $pathConfigFolder)) {
            # If the path does not exist, create the directory
            New-Item -ItemType Directory -Path $pathConfigFolder | Out-Null
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
            # Refresh the HTML inventory report alongside the freshly generated JSON.
            Write-SPSUpdateDbReport -JsonPath $spsUpdateDBsPath -ReportPath $spsUpdateDbReportPath
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
    'ResetStatus' {
        # Clear the status store campaign folder so a fresh patching round starts clean,
        # then create the folder and an empty "waiting" dashboard so it can be opened in a
        # browser before the ProductUpdate runs and the master Default run begin.
        try {
            if ([string]::IsNullOrEmpty($statusCampaignPath)) {
                Write-Warning -Message 'No status store campaign path resolved; nothing to reset.'
            }
            else {
                if (Test-Path -Path $statusCampaignPath) {
                    Write-Output "Resetting patching status store campaign: $statusCampaignPath"
                    Get-ChildItem -Path $statusCampaignPath -File -ErrorAction SilentlyContinue |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-Output 'Status store campaign cleared.'
                }
                else {
                    Write-Output "Creating patching status store campaign: $statusCampaignPath"
                    New-Item -Path $statusCampaignPath -ItemType Directory -Force | Out-Null
                }
                # Generate the empty dashboard now so it is ready to open before patching.
                Write-SPSDashboard
                if (-not [string]::IsNullOrEmpty($statusDashboardPath)) {
                    Write-Output "Live dashboard ready (open it in a browser): $statusDashboardPath"
                }
            }
        }
        catch {
            $catchMessage = @"
Failed to reset the status store campaign: $($statusCampaignPath)
Exception: $_
"@
            Write-Error -Message $catchMessage
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Set-SPSUpdateStatus' -EntryType 'Error'
        }
    }
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
                # Generate the self-contained HTML inventory report.
                Write-SPSUpdateDbReport -JsonPath $spsUpdateDBsPath -ReportPath $spsUpdateDbReportPath
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
        # Remove the stored secret from secrets.psd1 (if present)
        try {
            Set-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder -Remove
            Write-Output "Removed secret '$($envCfg.CredentialKey)' from Config\secrets.psd1 (if it was present)."
        }
        catch {
            # Handle errors during secret removal
            $catchMessage = @"
Failed to remove secret '$($envCfg.CredentialKey)' from Config\secrets.psd1 for SPFarm: $($spFarmName)
Exception: $_
"@
            Write-Error -Message $catchMessage
            Add-SPSUpdateEvent -Message $catchMessage -Source 'Set-SPSSecret' -EntryType 'Error'
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
                # Persist the InstallAccount as a DPAPI-encrypted SecureString in secrets.psd1.
                # Run -Action Install AS the InstallAccount so it can be decrypted at run time.
                try {
                    Set-SPSSecret -CredentialKey $envCfg.CredentialKey -Credential $InstallAccount -ConfigPath $pathConfigFolder
                    Write-Output "Stored secret '$($envCfg.CredentialKey)' in Config\secrets.psd1."
                }
                catch {
                    # Handle errors during secret storage
                    $catchMessage = @"
Failed to store secret '$($envCfg.CredentialKey)' in Config\secrets.psd1 for SPFarm: $($spFarmName)
Exception: $_
"@
                    Write-Error -Message $catchMessage
                    Add-SPSUpdateEvent -Message $catchMessage -Source 'Set-SPSSecret' -EntryType 'Error'
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
            if ($envCfg.UpgradeContentDatabase -or $envCfg.MountContentDatabase) {
                # Get credential from the DPAPI secret store; fall back to the InstallAccount
                $credential = Get-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder
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
        Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -State 'Running' -Detail "Installing $(@($envCfg.Binaries.SetupFileName).Count) update(s)"
        Write-SPSDashboard
        try {
            foreach ($setupFile in $envCfg.Binaries.SetupFileName) {
                $fullSetupFilePath = Join-Path -Path $envCfg.Binaries.SetupFullPath -ChildPath $setupFile
                $spTargetServer = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName).ToString()
                Write-Output @"
Running ProductUpdate with following parameters:
SharePoint Server: $($spTargetServer)
Setup File Path: $($fullSetupFilePath)
Shutdown Services: $($envCfg.Binaries.ShutdownServices)
"@
                Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -State 'Running' -Item $setupFile -ItemState 'Running' -ItemDetail 'installing'
                Write-SPSDashboard
                # NOTE: Pending reboot detection was removed because on production farms the
                # Windows reboot markers (CBS, PendingFileRenameOperations, etc.) commonly
                # remain set after several reboots, which caused the script to abort the
                # ProductUpdate even when the system was actually in a healthy state.
                # Unblock setup file if it is blocked
                Unblock-File -Path $fullSetupFilePath -Verbose
                $puExitCode = Start-SPSProductUpdate -SetupFile $fullSetupFilePath -ShutdownServices $envCfg.Binaries.ShutdownServices -Verbose
                if ($null -eq $puExitCode) {
                    # No install happened: already at or above the patch level.
                    Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Item $setupFile -ItemState 'Done' -ItemDetail 'already installed'
                }
                else {
                    $puDetail = switch ([int]$puExitCode) {
                        0 { 'installed' }
                        17022 { 'installed - reboot required' }
                        17025 { 'already installed' }
                        default { "installed (exit $puExitCode)" }
                    }
                    Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Item $setupFile -ItemState 'Done' -ItemDetail $puDetail -ExitCode ([int]$puExitCode)
                }
                Write-SPSDashboard
            }
            Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -State 'Done' -Detail 'All updates processed'
            Write-SPSDashboard
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
            Write-SPSStatus -Scope 'ProductUpdate' -Phase 'ProductUpdate' -State 'Failed' -Detail "$($_.Exception.Message)"
            Write-SPSDashboard
            if ($script:TranscriptStarted) {
                Stop-Transcript | Out-Null
                $script:TranscriptStarted = $false
            }
            exit
        }
    }
    Default {
        if ($PSBoundParameters.ContainsKey('Sequence')) {
            $seqScope = "Sequence$Sequence"
            $seqPhase = if ($envCfg.MountContentDatabase) { 'Mount' } else { 'Upgrade' }
            try {
                Write-Output "Update Script in progress | Sequence $Sequence  - Please Wait ..."
                switch ($Sequence) {
                    1 { $dbs = $jsonDbCfg.SPContentDatabase1 }
                    2 { $dbs = $jsonDbCfg.SPContentDatabase2 }
                    3 { $dbs = $jsonDbCfg.SPContentDatabase3 }
                    4 { $dbs = $jsonDbCfg.SPContentDatabase4 }
                }
                $dbList = @($dbs)
                $dbTotal = $dbList.Count
                $dbDone = 0
                Write-SPSStatus -Scope $seqScope -Phase $seqPhase -State 'Running' -Percent 0 -Detail "$dbTotal database(s)"
                foreach ($db in $dbList) {
                    # Mount SPContentDatabase (typically used to attach databases coming from a
                    # previous farm version, for example SP2019 -> Subscription Edition migration).
                    # Mounts run inside each Sequence scheduled task, so the 4 sequences process
                    # their respective DB groups in parallel. Each database list is loaded from
                    # the ContentDatabase inventory JSON file produced by Initialize-SPSContentDbJsonFile.
                    # Mount and Upgrade are independent: a farm can be configured for Mount only,
                    # Upgrade only, or both (Mount then Upgrade for SP2019 -> SE migration).
                    Write-SPSStatus -Scope $seqScope -Phase $seqPhase -Item "$($db.Name)" -ItemState 'Running' -ItemDetail 'processing'
                    $dbFailed = $false
                    if ($envCfg.MountContentDatabase) {
                        try {
                            Mount-SPSContentDatabase -Name $db.Name -WebAppUrl $db.WebAppUrl -DatabaseServer $db.Server
                        }
                        catch {
                            $dbFailed = $true
                            $catchMessage = @"
Failed to Mount SPContentDatabase '$($db.Name)' on WebApplication '$($db.WebAppUrl)'
Target SPFarm: $($spFarmName)
Exception: $_
"@
                            Write-Error -Message $catchMessage
                            Add-SPSUpdateEvent -Message $catchMessage -Source 'Mount-SPSContentDatabase' -EntryType 'Error'
                            Write-SPSStatus -Scope $seqScope -Phase $seqPhase -Item "$($db.Name)" -ItemState 'Failed' -ItemDetail "Mount failed: $($_.Exception.Message)"
                        }
                    }
                    if (-not $dbFailed -and $envCfg.UpgradeContentDatabase) {
                        Update-SPSContentDatabase -Name $db.Name
                    }
                    if (-not $dbFailed) {
                        $dbDone++
                        $pct = if ($dbTotal -gt 0) { [int]([math]::Round($dbDone / $dbTotal * 100, 0)) } else { 100 }
                        Write-SPSStatus -Scope $seqScope -Phase $seqPhase -State 'Running' -Percent $pct -Item "$($db.Name)" -ItemState 'Done' -ItemDetail 'processed'
                    }
                }
                Write-SPSStatus -Scope $seqScope -Phase $seqPhase -State 'Done' -Percent 100 -Detail "$dbDone/$dbTotal processed"
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
                Write-SPSStatus -Scope $seqScope -Phase $seqPhase -State 'Failed' -Detail "$($_.Exception.Message)"
            }
        }
        else {
            # Initialize Security from the DPAPI secret store
            try {
                $credential = Get-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder
                if ($null -eq $credential) {
                    throw "Secret '$($envCfg.CredentialKey)' was not found in Config\secrets.psd1."
                }
            }
            catch {
                # Handle errors during Security initialization
                $catchMessage = @"
Failed to initialize Security from Config\secrets.psd1
The secret '$($envCfg.CredentialKey)' is not present. Run SPSUpdate.ps1 -Action Install as the
InstallAccount, or populate secrets.psd1 manually. See the wiki for details.
Exception: $_
"@
                Write-Error -Message $catchMessage
                Add-SPSUpdateEvent -Message $catchMessage -Source 'Get-SPSSecret' -EntryType 'Error'
                if ($script:TranscriptStarted) {
                    Stop-Transcript | Out-Null
                    $script:TranscriptStarted = $false
                }
                exit
            }
            Write-Output "Update Script in progress | FULL Mode - Please Wait ..."
            # Mount and/or Upgrade SPContentDatabase via parallel scheduled tasks.
            # The sequence tasks themselves decide what to do for each database based on
            # the MountContentDatabase and UpgradeContentDatabase flags in the config.
            if ($envCfg.UpgradeContentDatabase -or $envCfg.MountContentDatabase) {
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
                        # Refresh the dashboard right after each start so a sequence that
                        # already began writing its status shows up immediately.
                        Write-SPSDashboard
                        # Pause 60-90s between starts to avoid OWSTimer conflicts, but keep
                        # the dashboard live by regenerating it every ~10s during the wait
                        # (the started sequences write their per-database progress meanwhile).
                        $pauseSeconds = (Get-Random -Minimum 60 -Maximum 91)
                        Write-Output "Avoid conflicts with OWSTimer process - Pause $pauseSeconds seconds"
                        $waited = 0
                        while ($waited -lt $pauseSeconds) {
                            $chunk = [System.Math]::Min(10, ($pauseSeconds - $waited))
                            Start-Sleep -Seconds $chunk
                            $waited += $chunk
                            Write-SPSDashboard
                        }
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
                    # Refresh the live dashboard from the shared status store while the
                    # parallel sequence tasks write their progress into it.
                    Write-SPSDashboard
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
                    Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server $thisServer -State 'Skipped' -Detail 'No action required'
                }
                else {
                    Write-Output "Action Required on server: $($env:COMPUTERNAME). Proceeding to run Configuration Wizard."
                    Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server $thisServer -State 'Running' -Detail 'Running PSConfig'
                    Write-SPSDashboard
                    $wizResult = Start-SPSConfigExe
                    $wizExit = @($wizResult) | Where-Object { $_ -is [int] } | Select-Object -Last 1
                    $wizDetail = if ($null -ne $wizExit) { "PSConfig completed (exit $([int]$wizExit))" } else { 'PSConfig completed' }
                    Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server $thisServer -State 'Done' -Detail $wizDetail
                }
                Write-SPSDashboard
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
                Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server $thisServer -State 'Failed' -Detail "$($_.Exception.Message)"
                Write-SPSDashboard
            }

            # Run SPConfigWizard on other SharePoint Server
            $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
            foreach ($spServer in $spServers) {
                try {
                    # Get patch status on Master SharePoint Server
                    Write-Output "Getting Patch Status on server: $($spServer.Name)"
                    if ((Get-SPSServersPatchStatus -Server "$($spServer.Name)") -eq 'NoActionRequired') {
                        Write-Output "No Action Required on server: $($spServer.Name). Skipping Configuration Wizard."
                        Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server "$($spServer.Name)" -State 'Skipped' -Detail 'No action required'
                    }
                    else {
                        Write-Output "Action Required on server: $($spServer.Name). Proceeding to run Configuration Wizard."
                        $spTargetServer = "$($spServer.Name).$($scriptFQDN)"
                        Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server "$($spServer.Name)" -State 'Running' -Detail 'Running PSConfig (remote)'
                        Write-SPSDashboard
                        $wizResultRemote = Start-SPSConfigExeRemote -Server $spTargetServer -InstallAccount $credential
                        $wizExitRemote = @($wizResultRemote) | Where-Object { $_ -is [int] } | Select-Object -Last 1
                        $wizDetailRemote = if ($null -ne $wizExitRemote) { "PSConfig completed (exit $([int]$wizExitRemote))" } else { 'PSConfig completed' }
                        Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server "$($spServer.Name)" -State 'Done' -Detail $wizDetailRemote
                    }
                    Write-SPSDashboard
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
                    Write-SPSStatus -Scope 'Wizard' -Phase 'Wizard' -Server "$($spServer.Name)" -State 'Failed' -Detail "$($_.Exception.Message)"
                    Write-SPSDashboard
                }
            }

            # Enable SideBySideToken and run Copy-SPSideBySideFiles on master server
            if (-not([string]::IsNullOrEmpty($envCfg.SideBySideToken.BuildVersion))) {
                try {
                    Write-Output "Configuring SharePoint SideBySideToken on farm $($spFarmName)"
                    Write-SPSStatus -Scope 'SideBySide' -Phase 'SideBySide' -Server $thisServer -State 'Running' -Detail "Token $($envCfg.SideBySideToken.BuildVersion)"
                    Write-SPSDashboard
                    Set-SPSSideBySideToken -BuildVersion "$($envCfg.SideBySideToken.BuildVersion)" -EnableSideBySide $envCfg.SideBySideToken.Enable
                    Write-SPSStatus -Scope 'SideBySide' -Phase 'SideBySide' -Server $thisServer -State 'Done' -Detail 'Token configured'
                    Write-SPSDashboard
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
                    Write-SPSStatus -Scope 'SideBySide' -Phase 'SideBySide' -Server $thisServer -State 'Failed' -Detail "$($_.Exception.Message)"
                    Write-SPSDashboard
                }
            }

            # Run Copy-SPSideBySideFiles on other servers
            if ($envCfg.SideBySideToken.Enable) {
                $spServers = Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' -and $_.Address -ne "$($env:COMPUTERNAME)" }
                foreach ($spServer in $spServers) {
                    try {
                        $spTargetServer = "$($spServer.Name).$($scriptFQDN)"
                        Copy-SPSSideBySideFilesRemote -Server $spTargetServer -InstallAccount $credential
                        Write-SPSStatus -Scope 'SideBySide' -Phase 'SideBySide' -Server "$($spServer.Name)" -State 'Done' -Detail 'Side-by-side files copied'
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
                        Write-SPSStatus -Scope 'SideBySide' -Phase 'SideBySide' -Server "$($spServer.Name)" -State 'Failed' -Detail "$($_.Exception.Message)"
                    }
                }
            }

            # Final dashboard render: mark the campaign completed (auto-refresh off).
            Write-SPSDashboard -Completed
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
Remove-Module -Name 'SPSUpdate.Common' -ErrorAction SilentlyContinue
$error.Clear()
Exit
