#region Import Modules
# Import the custom module 'sps.util.psm1' from the script's directory
try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'sps.util.psm1') -Force
}
catch {
    # Handle errors during Import of helper module
    Write-Error -Message @"
Failed to import sps.util.psm1 module from path: $($script:PSScriptRoot)
Exception: $_
"@
    Exit
}
#endregion

function Get-SPSInstalledProductVersion {
    [OutputType([System.Version])]
    param ()

    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    if ($null -eq $fullPath) {
        Write-Error -Message 'SharePoint path {C:\Program Files\Common Files\microsoft shared\Web Server Extensions} does not exist'
    }
    else {
        return ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath.FullName)).FileVersion
    }
}

function Invoke-SPSCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $Credential, # Credential to be used for executing the command

        [Parameter()]
        [Object[]]
        $Arguments, # Optional arguments for the script block

        [Parameter(Mandatory = $true)]
        [ScriptBlock]
        $ScriptBlock, # Script block containing the commands to execute

        [Parameter(Mandatory = $true)]
        [System.String]
        $Server # Target server where the commands will be executed
    )
    $VerbosePreference = 'Continue'
    # Base script to ensure the SharePoint snap-in is loaded
    $installedVersion = Get-SPSInstalledProductVersion
    if ($installedVersion.ProductMajorPart -eq 15 -or $installedVersion.ProductBuildPart -le 12999)
    {
        $baseScript = @"
            if (`$null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue))
            {
                Add-PSSnapin Microsoft.SharePoint.PowerShell
            }
"@
    }
    else
    {
        $baseScript = ''
    }
    # Prepare the arguments for Invoke-Command
    $invokeArgs = @{
        ScriptBlock = [ScriptBlock]::Create($baseScript + $ScriptBlock.ToString())
    }
    # Add arguments if provided
    if ($null -ne $Arguments) {
        $invokeArgs.Add("ArgumentList", $Arguments)
    }
    # Ensure a credential is provided
    if ($null -eq $Credential) {
        throw 'You need to specify a Credential'
    }
    else {
        Write-Verbose -Message ("Executing using a provided credential and local PSSession " + "as user $($Credential.UserName)")
        # Running garbage collection to resolve issues related to Azure DSC extension use
        [GC]::Collect()
        # Create a new PowerShell session on the target server using the provided credentials
        $session = New-PSSession -ComputerName $Server `
            -Credential $Credential `
            -Authentication CredSSP `
            -Name "Microsoft.SharePoint.PSSession" `
            -SessionOption (New-PSSessionOption -OperationTimeout 0 -IdleTimeout 60000) `
            -ErrorAction Continue

        # Add the session to the invocation arguments if the session is created successfully
        if ($session) {
            $invokeArgs.Add("Session", $session)
        }
        try {
            # Invoke the command on the target server
            return Invoke-Command @invokeArgs -Verbose
        }
        catch {
            throw $_ # Throw any caught exceptions
        }
        finally {
            # Remove the session to clean up
            if ($session) {
                Remove-PSSession -Session $session
            }
        }
    }
}

function Add-SPSScheduledTask {
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $ExecuteAsCredential, # Credentials for Task Schedule

        [Parameter(Mandatory = $true)]
        [System.String]
        $ActionArguments, # Arguments for the task action

        [Parameter(Mandatory = $true)]
        [System.String]
        $Name, # Name of the scheduled task to be added

        [Parameter()]
        [System.String]
        $Description, # Description of the scheduled task to be added

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint' # Path of the task folder
    )

    # Initialize variables
    $TaskCmd = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' # Path to PowerShell executable
    $UserName = $ExecuteAsCredential.UserName
    $Password = $ExecuteAsCredential.GetNetworkCredential().Password

    # Connect to the local TaskScheduler Service
    $TaskSvc = New-Object -ComObject ('Schedule.service')
    $TaskSvc.Connect($env:COMPUTERNAME)

    # Check if the folder exists, if not, create it
    try {
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Attempt to get the task folder
    }
    catch {
        Write-Output "Task folder '$TaskPath' does not exist. Creating folder..."
        $RootFolder = $TaskSvc.GetFolder('\') # Get the root folder
        $RootFolder.CreateFolder($TaskPath) # Create the missing task folder
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Get the newly created folder
        Write-Output "Successfully created task folder '$TaskPath'"
    }

    # Retrieve the scheduled task
    $getScheduledTask = $TaskFolder.GetTasks(0) | Where-Object -FilterScript {
        $_.Name -eq $Name
    }

    if ($getScheduledTask) {
        Write-Warning -Message 'Scheduled Task already exists - skipping.' # Task already exists
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "Adding '$Name' script in Task Scheduler Service ..."

        # Get credentials for Task Schedule
        $TaskAuthor = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name # Author of the task
        $TaskUser = $UserName # Username for task registration
        $TaskUserPwd = $Password # Password for task registration

        # Add a new Task Schedule
        $TaskSchd = $TaskSvc.NewTask(0)
        $TaskSchd.RegistrationInfo.Description = "$($Description)" # Task description
        $TaskSchd.RegistrationInfo.Author = $TaskAuthor # Task author
        $TaskSchd.Principal.RunLevel = 1 # Task run level (1 = Highest)

        # Task Schedule - Modify Settings Section
        $TaskSettings = $TaskSchd.Settings
        $TaskSettings.AllowDemandStart = $true
        $TaskSettings.Enabled = $true
        $TaskSettings.Hidden = $false
        $TaskSettings.StartWhenAvailable = $true

        # Define the task action
        $TaskAction = $TaskSchd.Actions.Create(0) # 0 = Executable action
        $TaskAction.Path = $TaskCmd # Path to the executable
        $TaskAction.Arguments = $ActionArguments # Arguments for the executable

        try {
            # Register the task
            $TaskFolder.RegisterTaskDefinition($Name, $TaskSchd, 6, $TaskUser, $TaskUserPwd, 1)
            Write-Output "Successfully added '$Name' script in Task Scheduler Service"
        }
        catch {
            $catchMessage = @"
An error occurred while adding the script in scheduled task: $($Name)
ActionArguments: $($ActionArguments)
Exception: $($_.Exception.Message)
"@
            Write-Error -Message $catchMessage # Handle any errors during task registration
        }
    }
}

function Remove-SPSScheduledTask {
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name, # Name of the scheduled task to be removed

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint' # Path of the task folder
    )

    # Connect to the local TaskScheduler Service
    $TaskSvc = New-Object -ComObject ('Schedule.service')
    $TaskSvc.Connect($env:COMPUTERNAME)

    # Check if the folder exists
    try {
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Attempt to get the task folder
    }
    catch {
        Write-Output "Task folder '$TaskPath' does not exist."
    }

    # Retrieve the scheduled task
    $getScheduledTask = $TaskFolder.GetTasks(0) | Where-Object -FilterScript {
        $_.Name -eq $Name
    }

    if ($null -eq $getScheduledTask) {
        Write-Warning -Message 'Scheduled Task already removed - skipping.' # Task not found
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "Removing $($Name) script in Task Scheduler Service ..."
        try {
            $TaskFolder.DeleteTask($Name, $null) # Remove the task
            Write-Output "Successfully removed $($Name) script from Task Scheduler Service"
        }
        catch {
            $catchMessage = @"
An error occurred while removing the script in scheduled task: $($Name)
Exception: $($_.Exception.Message)
"@
            Write-Error -Message $catchMessage # Handle any errors during task removal
        }
    }
}

function Start-SPSScheduledTask {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )
    $getScheduledTask = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($getScheduledTask) {
        Start-ScheduledTask -TaskName $Name `
            -TaskPath 'SharePoint' `
            -ErrorAction SilentlyContinue
    }
    else {
        Write-Output "Scheduled Task $Name does not exist in SharePoint Task Path"
    }
}
