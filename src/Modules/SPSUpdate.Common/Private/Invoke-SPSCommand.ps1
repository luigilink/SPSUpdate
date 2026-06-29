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
    if ($installedVersion.ProductMajorPart -eq 15 -or $installedVersion.ProductBuildPart -le 12999) {
        $baseScript = @"
            if (`$null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue))
            {
                Add-PSSnapin Microsoft.SharePoint.PowerShell
            }
"@
    }
    else {
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
