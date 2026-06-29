function Get-SPSConfigRoot {
    <#
        .SYNOPSIS
        Resolves the default location of the Config folder.

        .DESCRIPTION
        The Config folder lives in src/Config/, two levels up from the module
        root (src/Modules/SPSUpdate.Common). This helper centralizes that path
        resolution so the secret accessors share one default. Callers always
        override it by passing -ConfigPath (the entry script passes the Config
        folder next to SPSUpdate.ps1).

        .EXAMPLE
        Get-SPSConfigRoot
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    if ([string]::IsNullOrEmpty($script:ModuleRoot)) {
        throw "Module is not loaded correctly: `$script:ModuleRoot is not set. Re-import SPSUpdate.Common."
    }

    $srcRoot = Split-Path -Parent (Split-Path -Parent $script:ModuleRoot)
    return Join-Path -Path $srcRoot -ChildPath 'Config'
}
