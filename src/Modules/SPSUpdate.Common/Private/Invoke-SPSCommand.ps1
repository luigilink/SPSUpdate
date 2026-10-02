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
        $Server, # Target server where the commands will be executed

        [Parameter()]
        [Switch]
        $AllowFallback # When set, fall back to Negotiate if the CredSSP session cannot be opened
    )
    $VerbosePreference = 'Continue'

    # Base script to ensure the SharePointServer module is loaded in the remote session.
    # SharePoint Server Subscription Edition exposes its cmdlets through the SharePointServer
    # module; load it idempotently before running the caller's script block.
    $baseScript = @"
            if (`$null -eq (Get-Module -Name SharePointServer))
            {
                Import-Module SharePointServer -Verbose:`$false -WarningAction SilentlyContinue
            }

"@

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

    Write-Verbose -Message ("Executing on '$Server' as user $($Credential.UserName) " + `
            "(CredSSP preferred$(if ($AllowFallback) { ', Negotiate fallback enabled' }))")

    # Running garbage collection to resolve issues related to Azure DSC extension use
    [GC]::Collect()

    # CredSSP first (it delegates the credential for the remote cmdlets' second hop to SQL /
    # a file share); Negotiate only when explicitly allowed, and it cannot delegate.
    $authChain = @('CredSSP')
    if ($AllowFallback) {
        $authChain += 'Negotiate'
    }

    $sessionOption = Get-SPSRemoteSessionOption
    $session = $null
    $lastError = $null
    foreach ($auth in $authChain) {
        try {
            $session = New-PSSession -ComputerName $Server `
                -Credential $Credential `
                -Authentication $auth `
                -Name "Microsoft.SharePoint.PSSession" `
                -SessionOption $sessionOption `
                -ErrorAction Stop
            if ($auth -ne 'CredSSP') {
                Write-Warning -Message ("CredSSP unavailable to '$Server'; using '$auth'. Second-hop steps " + `
                        "(SQL / file share) may fail without Kerberos delegation for $($Credential.UserName).")
            }
            break
        }
        catch {
            $lastError = $_
            Write-Warning -Message "Failed to open a '$auth' PSSession to '$Server': $($_.Exception.Message)"
        }
    }

    if ($null -eq $session) {
        if ($authChain.Count -eq 1) {
            # Keep the original CredSSP-only message for strict environments.
            throw "Failed to open a CredSSP PSSession to '$Server': $($lastError.Exception.Message)"
        }
        throw ("Failed to open a remote PSSession to '$Server' using any of: $($authChain -join ', '). " + `
                "Last error: $($lastError.Exception.Message)")
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
