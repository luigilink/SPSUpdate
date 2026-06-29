function Export-SPSUpdateDbReport {
    <#
        .SYNOPSIS
        Generates a self-contained HTML report from a ContentDatabase inventory JSON.

        .DESCRIPTION
        Export-SPSUpdateDbReport renders the ContentDatabase inventory produced by
        Initialize-SPSContentDbJsonFile (the <App>-<Env>-<Farm>-ContentDBs.json file,
        with its SPContentDatabase1..4 sequence arrays) as a single, dependency-free
        HTML file (no CDN, works offline on a SharePoint server).

        The report shows summary cards (total databases, total size, balance spread),
        a per-sequence distribution view (count / size / percentage bars reflecting the
        LPT balancing), and a sortable / filterable table of every database with its
        sequence, server, web application URL and size.

        Each database entry is expected to expose Name, Server, WebAppUrl and (since
        v4.1.0) SizeInMB / SizeInBytes. Inventories generated before v4.1.0 have no size
        information; the report still renders and shows 'n/a' for the missing sizes.

        The data can be supplied either as a file (-InputFile, the JSON inventory) or as
        an already-parsed object (-InputObject). Returns the path of the report written.

        .PARAMETER InputFile
        Path of the ContentDatabase inventory JSON file to read.

        .PARAMETER InputObject
        An already-parsed inventory object (with SPContentDatabase1..4 properties).

        .PARAMETER OutputFile
        Destination path of the generated .html file.

        .PARAMETER Title
        Heading shown at the top of the report. Defaults to a generic title.

        .PARAMETER EnvName
        Environment label shown in the metadata line (e.g. PROD).

        .PARAMETER AppCode
        Application code shown in the metadata line.

        .PARAMETER FarmName
        Farm label shown in the metadata line.

        .PARAMETER Version
        SPSUpdate version stamped in the report footer. Defaults to the module version.

        .EXAMPLE
        Export-SPSUpdateDbReport -InputFile $json -OutputFile $html -EnvName 'PROD' -AppCode 'contoso' -FarmName 'CONTENT'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByFile')]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'ByFile')]
        [System.String]
        $InputFile,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject')]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFile,

        [Parameter()]
        [System.String]
        $Title,

        [Parameter()]
        [System.String]
        $EnvName,

        [Parameter()]
        [System.String]
        $AppCode,

        [Parameter()]
        [System.String]
        $FarmName,

        [Parameter()]
        [System.String]
        $Version
    )

    # ---- Load the inventory -------------------------------------------------------
    if ($PSCmdlet.ParameterSetName -eq 'ByFile') {
        if (-not (Test-Path -Path $InputFile)) {
            throw "Export-SPSUpdateDbReport: input file not found: $InputFile"
        }
        $raw = Get-Content -Path $InputFile -Raw -Encoding UTF8
        $inventory = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
    }
    else {
        $inventory = $InputObject
    }

    if ([string]::IsNullOrEmpty($Title)) { $Title = 'SPSUpdate - ContentDatabase Inventory Report' }

    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = (Get-Module -Name SPSUpdate.Common -ErrorAction SilentlyContinue).Version
        $Version = if ($null -ne $moduleVersion) { $moduleVersion.ToString() } else { 'unknown' }
    }

    # ---- Flatten the four sequence arrays into rows -------------------------------
    $sequenceNames = @('SPContentDatabase1', 'SPContentDatabase2', 'SPContentDatabase3', 'SPContentDatabase4')
    $hasSize = $false
    $rows = New-Object System.Collections.Generic.List[object]
    $seqSummary = @()

    for ($s = 0; $s -lt $sequenceNames.Count; $s++) {
        $seqProp = $sequenceNames[$s]
        $seqLabel = "Sequence $($s + 1)"
        $dbs = @()
        if ($null -ne $inventory -and ($inventory.PSObject.Properties.Name -contains $seqProp)) {
            $dbs = @($inventory.$seqProp)
        }

        $seqCount = 0
        $seqBytes = [double]0
        foreach ($db in $dbs) {
            if ($null -eq $db) { continue }
            $seqCount++

            $sizeMbValue = $null
            if ($db.PSObject.Properties.Name -contains 'SizeInMB' -and $null -ne $db.SizeInMB -and "$($db.SizeInMB)" -ne '') {
                $hasSize = $true
                $sizeMbValue = [double]$db.SizeInMB
            }
            if ($db.PSObject.Properties.Name -contains 'SizeInBytes' -and $null -ne $db.SizeInBytes -and "$($db.SizeInBytes)" -ne '') {
                $seqBytes += [double]$db.SizeInBytes
            }
            elseif ($null -ne $sizeMbValue) {
                $seqBytes += $sizeMbValue * 1MB
            }

            $rows.Add([PSCustomObject][ordered]@{
                    Sequence  = $seqLabel
                    Name      = "$($db.Name)"
                    Server    = "$($db.Server)"
                    WebAppUrl = "$($db.WebAppUrl)"
                    SizeMB    = if ($null -ne $sizeMbValue) { $sizeMbValue } else { $null }
                })
        }

        $seqSummary += [PSCustomObject]@{
            Name   = $seqLabel
            Count  = $seqCount
            Bytes  = $seqBytes
            SizeMB = [System.Math]::Round($seqBytes / 1MB, 0)
        }
    }

    $totalDbs = ($seqSummary | Measure-Object -Property Count -Sum).Sum
    $totalBytes = ($seqSummary | Measure-Object -Property Bytes -Sum).Sum
    $totalMB = [System.Math]::Round($totalBytes / 1MB, 0)

    # Percentage per sequence (by size when known, otherwise by count).
    $distInput = foreach ($seq in $seqSummary) {
        $pct = if ($hasSize -and $totalBytes -gt 0) {
            [System.Math]::Round($seq.Bytes / $totalBytes * 100, 1)
        }
        elseif ($totalDbs -gt 0) {
            [System.Math]::Round($seq.Count / $totalDbs * 100, 1)
        }
        else { 0 }
        [PSCustomObject]@{
            Name    = $seq.Name
            Count   = $seq.Count
            SizeMB  = $seq.SizeMB
            Percent = $pct
        }
    }

    # Balance spread = max% - min% across sequences (lower is better).
    $pcts = @($distInput | ForEach-Object { [double]$_.Percent })
    $spread = if ($pcts.Count -gt 0) {
        [System.Math]::Round((($pcts | Measure-Object -Maximum).Maximum - ($pcts | Measure-Object -Minimum).Minimum), 1)
    }
    else { 0 }

    # ---- Summary cards ------------------------------------------------------------
    $cards = @(
        (Get-SPSReportCardHtml -Value $totalDbs -Label 'Content databases')
        (Get-SPSReportCardHtml -Value $(if ($hasSize) { '{0:N0}' -f $totalMB } else { 'n/a' }) -Label 'Total size (MB)')
        (Get-SPSReportCardHtml -Value '4' -Label 'Sequences')
        (Get-SPSReportCardHtml -Value $("{0:N1}%" -f $spread) -Label 'Balance spread' -Sub $(if ($hasSize) { 'by size' } else { 'by count' }) -Tone 'accent')
    ) -join ''

    $distHtml = Get-SPSReportDistributionHtml -Sequences $distInput
    $summaryInner = "<div class=`"cards`">$cards</div>" +
    "<h3 style=`"margin-top:16px`">Sequence distribution (LPT balancing)</h3>$distHtml"

    # ---- Table payload ------------------------------------------------------------
    $columns = @(
        @{ field = 'Sequence';  label = 'Sequence';     type = 'text' }
        @{ field = 'Name';      label = 'Database';      type = 'text' }
        @{ field = 'Server';    label = 'Server';        type = 'text' }
        @{ field = 'WebAppUrl'; label = 'Web App';       type = 'text' }
        @{ field = 'SizeMB';    label = 'Size (MB)';     type = 'num' }
    )

    $tableRows = foreach ($row in $rows) {
        [PSCustomObject][ordered]@{
            Sequence  = $row.Sequence
            Name      = $row.Name
            Server    = $row.Server
            WebAppUrl = $row.WebAppUrl
            SizeMB    = if ($null -ne $row.SizeMB) { ('{0:N0}' -f [double]$row.SizeMB) } else { 'n/a' }
        }
    }

    $payload = [ordered]@{
        columns = $columns
        rows    = @($tableRows)
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    # Neutralize any sequence that could break out of the <script> block
    $json = $json -replace '<', '\u003c' -replace '>', '\u003e' -replace '&', '\u0026'

    # ---- Metadata -----------------------------------------------------------------
    $encTitle = ConvertTo-SPSHtmlEncoded -Value $Title
    $encEnv = ConvertTo-SPSHtmlEncoded -Value $EnvName
    $encApp = ConvertTo-SPSHtmlEncoded -Value $AppCode
    $encFarm = ConvertTo-SPSHtmlEncoded -Value $FarmName
    $encVersion = ConvertTo-SPSHtmlEncoded -Value $Version
    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm'

    $metaParts = @()
    if (-not [string]::IsNullOrEmpty($encApp)) { $metaParts += "AppCode: $encApp" }
    if (-not [string]::IsNullOrEmpty($encEnv)) { $metaParts += "Environment: $encEnv" }
    if (-not [string]::IsNullOrEmpty($encFarm)) { $metaParts += "Farm: $encFarm" }
    $metaParts += "Generated: $generated"
    $metaParts += "SPSUpdate $encVersion"
    $metaLine = $metaParts -join ' &middot; '

    $noSizeNote = if (-not $hasSize) {
        "<div class=`"meta`">No size information in this inventory (generated before v4.1.0); distribution is shown by database count.</div>"
    }
    else { '' }

    # ---- Assemble the document ----------------------------------------------------
    $html = (Get-SPSReportHtmlHead -Title $encTitle) +
    "<h1>$encTitle</h1>" +
    "<div class=`"meta`">$metaLine</div>" +
    "<div class=`"summary`"><h3 style=`"margin-top:0`">Summary</h3>$summaryInner</div>" +
    '<h2>Databases</h2>' +
    $noSizeNote +
    '<div class="controls"><input id="spsSearch" class="search" placeholder="Filter databases..."><div class="pager"><button id="spsPrev">Prev</button><span id="spsPageInfo"></span><button id="spsNext">Next</button></div></div>' +
    '<table><thead id="spsThead"></thead><tbody id="spsTbody"></tbody></table>' +
    "<div class=`"footer`">Generated by SPSUpdate $encVersion from the ContentDatabase inventory. The four sequences are balanced with a Longest-Processing-Time-First heuristic so the parallel mount/upgrade tasks finish closer together.</div>" +
    "<script type=`"application/json`" id=`"spsReportData`">$json</script>" +
    (Get-SPSReportHtmlScript) +
    '</body></html>'

    $outDir = Split-Path -Path $OutputFile -Parent
    if (-not [string]::IsNullOrEmpty($outDir) -and -not (Test-Path -Path $outDir)) {
        $null = New-Item -Path $outDir -ItemType Directory -Force
    }
    Set-Content -Path $OutputFile -Value $html -Force -Encoding UTF8

    return $OutputFile
}
