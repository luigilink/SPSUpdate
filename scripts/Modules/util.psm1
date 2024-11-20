#region Import Modules
# Import the custom module 'sps.util.psm1' from the script's directory
$scriptModulePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Name (Join-Path -Path $scriptModulePath -ChildPath 'sps.util.psm1') -Force
#endregion

function Get-SPSInstalledProductVersion {
    [OutputType([System.Version])]
    param ()

    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
    if ($null -eq $fullPath) {
        throw 'SharePoint path {C:\Program Files\Common Files\microsoft shared\Web Server Extensions} does not exist'
    }
    else {
        return (Get-Command $fullPath).FileVersionInfo
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
    $baseScript = @"
    if (`$null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue))
    {
        Add-PSSnapin Microsoft.SharePoint.PowerShell
    }
"@

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

function Clear-SPSLog {
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $path, # Path to the log files

        [Parameter()]
        [System.UInt32]
        $Retention = 180 # Number of days to retain log files
    )
    # Check if the log file path exists
    if (Test-Path $path) {
        # Get the current date
        $Now = Get-Date
        # Define LastWriteTime parameter based on $Retention
        $LastWrite = $Now.AddDays(-$Retention)
        # Get files based on last write filter and specified folder
        $files = Get-ChildItem -Path $path -Filter "$($logFileName)*" | Where-Object -FilterScript {
            $_.LastWriteTime -le "$LastWrite"
        }
        # If files are found, proceed to delete them
        if ($files) {
            Write-Output '--------------------------------------------------------------'
            Write-Output "Cleaning log files in $path ..."
            foreach ($file in $files) {
                if ($null -ne $file) {
                    Write-Output "Deleting file $file ..."
                    Remove-Item $file.FullName | Out-Null
                }
                else {
                    Write-Output 'No more log files to delete'
                    Write-Output '--------------------------------------------------------------'
                }
            }
        }
        else {
            Write-Output '--------------------------------------------------------------'
            Write-Output "$path - No needs to delete log files"
            Write-Output '--------------------------------------------------------------'
        }
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "$path does not exist"
        Write-Output '--------------------------------------------------------------'
    }
}

function Add-SPSScheduledTask {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Description,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PSArguments,

        [Parameter()]
        [System.String]
        $StartTime
    )

    $fullScriptPath = Join-Path -Path $scriptRootPath -ChildPath $item.Name
    $taskArgs = @{
        TaskName            = $Name
        TaskPath            = 'SharePoint'
        ScheduleType        = 'Once'
        Enable              = $true
        ActionExecutable    = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        ActionArguments     = "-ExecutionPolicy Bypass $($fullScriptPath) $($PSArguments)"
        ExecuteAsCredential = $FSP
        Description         = $Description
        RunLevel            = 'Highest'
    }

    $getScheduledTask = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -eq $getScheduledTask) {
        if ([string]::IsNullOrEmpty($StartTime)) {
            Set-TargetResource @taskArgs
        }
        else {
            Set-TargetResource @taskArgs -StartTime $StartTime
        }
    }
    else {
        Write-Output "Scheduled Task $Name already added in SharePoint Task Path"
    }
}

function Remove-SPSScheduledTask {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )
    $taskArgs = @{
        TaskName            = $Name
        TaskPath            = 'SharePoint'
        ScheduleType        = 'Once'
        Enable              = $false
        Ensure              = 'Absent'
        ActionExecutable    = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        ActionArguments     = ''
        ExecuteAsCredential = $FSP
        Description         = $Description
        RunLevel            = 'Highest'
    }
    $getScheduledTask = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($getScheduledTask) {
        Set-TargetResource @taskArgs
    }
    else {
        Write-Output "Scheduled Task $Name already removed from SharePoint Task Path"
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
