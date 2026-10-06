function ConvertTo-SPSRoleLabel {
    <#
        .SYNOPSIS
        Maps a SharePoint server MinRole to a short, readable dashboard label.

        .DESCRIPTION
        Translates the raw SPServer Role (MinRole) enum values returned by Get-SPServer (for
        example 'WebFrontEndWithDistributedCache') into the short labels shown on the dashboard
        (for example 'Front-end with Distributed Cache'), aligned with the Central Administration
        "Servers in Farm" wording but kept concise. An already-friendly label or an unknown value
        is returned unchanged, so the function is idempotent.

        .PARAMETER Role
        The raw role string/enum value. Empty or whitespace returns an empty string.

        .EXAMPLE
        ConvertTo-SPSRoleLabel -Role 'ApplicationWithSearch'   # -> 'Application with Search'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Role
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Role)) { return '' }
        switch ("$Role".Trim()) {
            'Application' { 'Application'; break }
            'ApplicationWithSearch' { 'Application with Search'; break }
            'WebFrontEnd' { 'Front-end'; break }
            'WebFrontEndWithDistributedCache' { 'Front-end with Distributed Cache'; break }
            'DistributedCache' { 'Distributed Cache'; break }
            'Search' { 'Search'; break }
            'SingleServerFarm' { 'Single-Server Farm'; break }
            'Custom' { 'Custom'; break }
            # Already a friendly label, or an unknown enum: return as-is (idempotent).
            default { "$Role".Trim() }
        }
    }
}
