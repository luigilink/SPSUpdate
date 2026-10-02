function Copy-SPSSideBySideFilesRemote {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter()]
        [Switch]
        $AllowFallback
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
        -Server $Server `
        -AllowFallback:$AllowFallback `
        -ScriptBlock {
        $params = $args[0]

        Write-Output "Running CmdLet Copy-SPSideBySideFiles on server: $($params.Server)"
        Copy-SPSideBySideFiles -Verbose
    }
    return $result
}

Set-Alias -Name Copy-SPSSideBySideFilesAllServers -Value Copy-SPSSideBySideFilesRemote
