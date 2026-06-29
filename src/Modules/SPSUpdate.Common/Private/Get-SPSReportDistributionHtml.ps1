function Get-SPSReportDistributionHtml {
    <#
        .SYNOPSIS
        Builds the per-sequence distribution bars (count / MB / percentage).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Sequences
    )

    $rowsHtml = ''
    foreach ($seq in $Sequences) {
        $pct = [double]$seq.Percent
        $encName = ConvertTo-SPSHtmlEncoded -Value $seq.Name
        $valText = '{0} db &middot; {1:N0} MB &middot; {2:N1}%' -f $seq.Count, $seq.SizeMB, $pct
        $rowsHtml += "<div class=`"dist-row`"><div class=`"dist-name`">$encName</div>" +
        "<div class=`"dist-track`"><div class=`"dist-fill`" style=`"width:$([System.Math]::Round($pct,1))%`"></div></div>" +
        "<div class=`"dist-val`">$valText</div></div>"
    }
    return "<div class=`"dist`">$rowsHtml</div>"
}
