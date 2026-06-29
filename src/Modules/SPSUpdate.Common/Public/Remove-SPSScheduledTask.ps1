function Remove-SPSScheduledTask {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
            if ($PSCmdlet.ShouldProcess($Name, 'Remove scheduled task')) {
                $TaskFolder.DeleteTask($Name, $null) # Remove the task
                Write-Output "Successfully removed $($Name) script from Task Scheduler Service"
            }
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
