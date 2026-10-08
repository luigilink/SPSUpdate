function ConvertTo-SPSConfigBoolean {
    <#
        .SYNOPSIS
        Validates and normalizes a Boolean configuration value.

        .DESCRIPTION
        ConvertTo-SPSConfigBoolean gives every Boolean switch in the SPSUpdate
        configuration the same, predictable contract. It accepts a real Boolean
        ($true / $false) or the integers 1 / 0, and returns the corresponding
        [bool]. Any other value (an out-of-range integer, a string such as 'true'
        or 'yes', $null, ...) throws a clear error naming the property, so a typo
        in the psd1 fails fast instead of being silently coerced to $true.

        Only genuine integer types are accepted for the 1/0 form; a string like
        '1' is rejected on purpose, to avoid the PowerShell footgun where
        [bool]'false' evaluates to $true.

        .PARAMETER Value
        The raw value read from the configuration for the property.

        .PARAMETER PropertyName
        The dotted property path (for example 'Reboot.Enable') used in the error
        message so the operator knows exactly which key to fix.

        .EXAMPLE
        ConvertTo-SPSConfigBoolean -Value 1 -PropertyName 'Reboot.Enable'

        .EXAMPLE
        ConvertTo-SPSConfigBoolean -Value $false -PropertyName 'Remoting.AllowFallback'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PropertyName
    )

    if ($Value -is [bool]) {
        return $Value
    }

    # Accept any integral type valued 0 or 1; the type guard keeps strings like '0'/'1'
    # out (otherwise '0' -eq 0 would match via PowerShell string coercion).
    $integralTypes = @([byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64])
    if (($null -ne $Value) -and ($Value.GetType() -in $integralTypes) -and ($Value -eq 0 -or $Value -eq 1)) {
        return [System.Boolean][int64]$Value
    }

    throw "Configuration property '$PropertyName' must be a Boolean (`$true/`$false) or 0/1, not '$Value'."
}
