function Get-SPSReportCardHtml {
    <#
        .SYNOPSIS
        Builds the HTML for one summary "card" (a big number plus a label).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Label,

        [Parameter()]
        [System.String]
        $Sub = '',

        [Parameter()]
        [ValidateSet('', 'accent')]
        [System.String]
        $Tone = ''
    )

    $encValue = ConvertTo-SPSHtmlEncoded -Value ("$Value")
    $encLabel = ConvertTo-SPSHtmlEncoded -Value $Label
    $encSub = ConvertTo-SPSHtmlEncoded -Value $Sub
    $toneClass = if ([string]::IsNullOrEmpty($Tone)) { '' } else { " $Tone" }
    $subHtml = if ([string]::IsNullOrEmpty($encSub)) { '' } else { "<div class=`"card-sub`">$encSub</div>" }
    return "<div class=`"card$toneClass`"><div class=`"card-value`">$encValue</div><div class=`"card-label`">$encLabel</div>$subHtml</div>"
}
