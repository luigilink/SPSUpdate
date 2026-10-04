function Get-SPSRemoteSessionOption {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Remoting.PSSessionOption])]
    param ()

    # WinRM timeouts; isolated here because these options are Windows-only (keeps the caller
    # unit-testable on any platform).
    return New-PSSessionOption -OperationTimeout 0 -IdleTimeout 60000 -OpenTimeout 30000
}
