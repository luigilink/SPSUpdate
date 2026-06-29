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

    Write-Output '--------------------------------------------------------------'
    Write-Output "Adding or updating '$Name' script in Task Scheduler Service ..."

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
        # Register/update the task (6 = create or update). Cast to [void] so the
        # returned RegisteredTask COM object is not dumped into the transcript.
        [void]$TaskFolder.RegisterTaskDefinition($Name, $TaskSchd, 6, $TaskUser, $TaskUserPwd, 1)
        Write-Output "Successfully added or updated '$Name' script in Task Scheduler Service"
    }
    catch {
        $catchMessage = @"
An error occurred while adding/updating the script in scheduled task: $($Name)
ActionArguments: $($ActionArguments)
Exception: $($_.Exception.Message)
"@
        Write-Error -Message $catchMessage # Handle any errors during task registration
    }
}
