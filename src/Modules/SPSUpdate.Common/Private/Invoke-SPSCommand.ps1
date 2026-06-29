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

    # Base script to ensure the SharePoint snap-in is loaded. On SharePoint 2016/2019
    # the legacy PSSnapin is required; on Subscription Edition the SharePointServer
    # module is auto-loaded, so no base script is prepended.
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
    if ($null -ne $Arguments) {
        $invokeArgs.Add("ArgumentList", $Arguments)
    }
    if ($null -eq $Credential) {
        throw 'You need to specify a Credential'
    }

    Write-Verbose -Message ("Executing on '$Server' using a CredSSP PSSession " + `
            "as user $($Credential.UserName)")

    # Running garbage collection to resolve issues related to Azure DSC extension use
    [GC]::Collect()

    # Open the remote session, failing clearly instead of silently running the
    # SharePoint scriptblock on the local server when the CredSSP session cannot be
    # established (e.g. CredSSP not configured, or the target server is unreachable).
    try {
        $session = New-PSSession -ComputerName $Server `
            -Credential $Credential `
            -Authentication CredSSP `
            -Name "Microsoft.SharePoint.PSSession" `
            -SessionOption (New-PSSessionOption -OperationTimeout 0 `
                -IdleTimeout 60000 `
                -OpenTimeout 30000) `
            -ErrorAction Stop
    }
    catch {
        throw "Failed to open a CredSSP PSSession to '$Server': $($_.Exception.Message)"
    }

    $invokeArgs.Add("Session", $session)

    try {
        return Invoke-Command @invokeArgs -Verbose
    }
    catch {
        throw "Remote command on '$Server' failed: $($_.Exception.Message)"
    }
    finally {
        Remove-PSSession -Session $session
    }
}
