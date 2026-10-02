function Get-SPSRemoteSessionOption {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Remoting.PSSessionOption])]
    param ()

    # WinRM session timeouts for the SharePoint remote session. These options only exist on
    # the Windows New-PSSessionOption; isolating the call in this wrapper keeps the
    # Windows-only dependency out of Invoke-SPSCommand so it stays unit-testable on any platform.
    return New-PSSessionOption -OperationTimeout 0 -IdleTimeout 60000 -OpenTimeout 30000
}
