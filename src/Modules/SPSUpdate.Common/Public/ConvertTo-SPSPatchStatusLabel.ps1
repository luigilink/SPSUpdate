function ConvertTo-SPSPatchStatusLabel {
    <#
        .SYNOPSIS
        Maps a SharePoint server patch StatusType to a short, readable dashboard label.

        .DESCRIPTION
        Translates the raw SPServerProductInfo StatusType enum values returned by
        Get-SPSServersPatchStatus (for example 'UpgradeRequired') into the short labels shown on
        the dashboard (for example 'Upgrade Required'), aligned with the Central Administration
        "Servers in Farm" wording but kept concise. An already-friendly label or an unknown value
        is returned unchanged, so the function is idempotent.

        .PARAMETER Status
        The raw status string/enum value. Empty or whitespace returns an empty string.

        .EXAMPLE
        ConvertTo-SPSPatchStatusLabel -Status 'UpgradeRequired'   # -> 'Upgrade Required'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Status
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Status)) { return '' }
        switch ("$Status".Trim()) {
            'NoActionRequired' { 'No Action Required'; break }
            'InstallRequired' { 'Installation Required'; break }
            'UpgradeAvailable' { 'Upgrade Available'; break }
            'UpgradeRequired' { 'Upgrade Required'; break }
            'UpgradeBlocked' { 'Upgrade Blocked'; break }
            'UpgradeInProgress' { 'Upgrade in Progress'; break }
            # Already a friendly label, or an unknown enum: return as-is (idempotent).
            default { "$Status".Trim() }
        }
    }
}
