function Export-SPSUpdateProgressReport {
    <#
        .SYNOPSIS
        Renders the live patching progress dashboard from the status store.

        .DESCRIPTION
        Export-SPSUpdateProgressReport reads every status scope of a campaign (via
        Get-SPSUpdateStatus) and renders a single, self-contained HTML dashboard that
        shows the overall patching progress and the detail of each phase
        (ProductUpdate per server, the four upgrade/mount sequences, the post-setup
        Configuration Wizard per server, and side-by-side). It is regenerated
        periodically by the master during the run, and the page carries a meta-refresh
        so an open browser updates on its own.

        The dashboard is fully server-rendered (no fetch), so it works from a file
        share opened over file:// as well as over HTTP. All values are HTML-encoded.

        Returns the path of the dashboard that was written.

        .PARAMETER CampaignPath
        Folder of the patching campaign to read (the campaign status files live here,
        and the dashboard is written here by default).

        .PARAMETER OutputFile
        Destination path of the dashboard. Defaults to '_dashboard.html' in CampaignPath.

        .PARAMETER Title
        Heading shown at the top. Defaults to a generic title.

        .PARAMETER EnvName
        Environment label shown in the metadata line.

        .PARAMETER AppCode
        Application code shown in the metadata line.

        .PARAMETER FarmName
        Farm label shown in the metadata line.

        .PARAMETER RefreshSeconds
        Meta-refresh interval (seconds). 0 disables auto-refresh. Default 15.

        .PARAMETER Completed
        Mark the campaign as completed: disables the auto-refresh and shows a final state.

        .PARAMETER Version
        SPSUpdate version stamped in the footer. Defaults to the module version.

        .EXAMPLE
        Export-SPSUpdateProgressReport -CampaignPath $c -EnvName 'PROD' -AppCode 'contoso' -FarmName 'CONTENT'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CampaignPath,

        [Parameter()]
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
        [System.Int32]
        $RefreshSeconds = 15,

        [Parameter()]
        [switch]
        $Completed,

        [Parameter()]
        [System.String]
        $Version
    )

    if ([string]::IsNullOrEmpty($OutputFile)) {
        $OutputFile = Join-Path -Path $CampaignPath -ChildPath '_dashboard.html'
    }
    if ([string]::IsNullOrEmpty($Title)) { $Title = 'SPSUpdate - Patching Progress' }
    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = (Get-Module -Name SPSUpdate.Common -ErrorAction SilentlyContinue).Version
        $Version = if ($null -ne $moduleVersion) { $moduleVersion.ToString() } else { 'unknown' }
    }

    $scopes = @(Get-SPSUpdateStatus -CampaignPath $CampaignPath)

    # Helper: a colored state badge.
    $badge = {
        param($state)
        $s = if ([string]::IsNullOrEmpty($state)) { 'Pending' } else { "$state" }
        $encoded = ConvertTo-SPSHtmlEncoded -Value $s
        "<span class=`"badge $s`">$encoded</span>"
    }

    # ---- Overall roll-up ----------------------------------------------------------
    $allItemStates = New-Object System.Collections.Generic.List[string]
    foreach ($sc in $scopes) {
        if ($sc.State) { $allItemStates.Add("$($sc.State)") }
        foreach ($it in @($sc.Items)) { if ($it.State) { $allItemStates.Add("$($it.State)") } }
    }
    $countFailed = @($allItemStates | Where-Object { $_ -eq 'Failed' }).Count
    $countRunning = @($allItemStates | Where-Object { $_ -eq 'Running' }).Count
    $countDone = @($allItemStates | Where-Object { $_ -eq 'Done' }).Count
    $countPending = @($allItemStates | Where-Object { $_ -eq 'Pending' }).Count
    $countWarning = @($allItemStates | Where-Object { $_ -eq 'Warning' }).Count

    $overall = if ($scopes.Count -eq 0) { 'Pending' }
    elseif ($countFailed -gt 0) { 'Failed' }
    elseif ($countRunning -gt 0 -or $countPending -gt 0) { 'Running' }
    elseif ($countWarning -gt 0) { 'Warning' }
    else { 'Done' }
    if ($Completed -and $overall -eq 'Running') { $overall = 'Done' }

    $serverCount = @($scopes | Select-Object -ExpandProperty Server -Unique | Where-Object { $_ }).Count

    # ---- Summary cards ------------------------------------------------------------
    $cards = @(
        "<div class=`"card accent`"><div class=`"card-value`">$(& $badge $overall)</div><div class=`"card-label`">Overall state</div></div>"
        (Get-SPSReportCardHtml -Value $serverCount -Label 'Servers')
        (Get-SPSReportCardHtml -Value $countDone -Label 'Done')
        (Get-SPSReportCardHtml -Value $countRunning -Label 'Running')
        (Get-SPSReportCardHtml -Value $countFailed -Label 'Failed')
    ) -join ''

    # ---- Phase sections -----------------------------------------------------------
    $phaseOrder = @('ProductUpdate', 'Mount', 'Upgrade', 'Sequence', 'Wizard', 'SideBySide')
    $phaseLabels = @{
        ProductUpdate = 'Product update (binaries)'
        Mount         = 'Content database mount'
        Upgrade       = 'Content database upgrade'
        Sequence      = 'Content database sequences'
        Wizard        = 'Configuration Wizard (PSConfig)'
        SideBySide    = 'Side-by-side token'
    }

    $sections = ''
    $presentPhases = @($scopes | Select-Object -ExpandProperty Phase -Unique)
    $orderedPhases = @($phaseOrder | Where-Object { $presentPhases -contains $_ })
    $orderedPhases += @($presentPhases | Where-Object { $phaseOrder -notcontains $_ })

    foreach ($phase in $orderedPhases) {
        $phaseScopes = @($scopes | Where-Object { $_.Phase -eq $phase } | Sort-Object Server, Scope)
        if ($phaseScopes.Count -eq 0) { continue }
        $label = if ($phaseLabels.ContainsKey($phase)) { $phaseLabels[$phase] } else { $phase }
        $sections += "<div class=`"phase`"><h2>$(ConvertTo-SPSHtmlEncoded -Value $label)</h2>"

        foreach ($sc in $phaseScopes) {
            $encServer = ConvertTo-SPSHtmlEncoded -Value "$($sc.Server)"
            $encScope = ConvertTo-SPSHtmlEncoded -Value "$($sc.Scope)"
            $encDetail = ConvertTo-SPSHtmlEncoded -Value "$($sc.Detail)"
            $pctText = if ($null -ne $sc.Percent -and "$($sc.Percent)" -ne '') { " &middot; $([int]$sc.Percent)%" } else { '' }
            $updated = ''
            if ($sc.UpdatedAt) {
                try { $updated = " &middot; updated $([datetime]::Parse($sc.UpdatedAt).ToString('HH:mm:ss'))" } catch { $updated = '' }
            }

            $sections += "<div class=`"scope`"><div class=`"scope-head`">$(& $badge $sc.State) $encServer / $encScope$pctText</div>"
            if (-not [string]::IsNullOrEmpty($encDetail)) {
                $sections += "<div class=`"scope-detail`">$encDetail$updated</div>"
            }
            elseif (-not [string]::IsNullOrEmpty($updated)) {
                $sections += "<div class=`"scope-detail`">$($updated.TrimStart(' &middot;'))</div>"
            }

            $items = @($sc.Items)
            if ($items.Count -gt 0) {
                $rows = ''
                foreach ($it in $items) {
                    $encName = ConvertTo-SPSHtmlEncoded -Value "$($it.Name)"
                    $encItemDetail = ConvertTo-SPSHtmlEncoded -Value "$($it.Detail)"
                    $exit = if ($null -ne $it.ExitCode -and "$($it.ExitCode)" -ne '') { ConvertTo-SPSHtmlEncoded -Value "$($it.ExitCode)" } else { '' }
                    $rows += "<tr><td>$encName</td><td>$(& $badge $it.State)</td><td>$encItemDetail</td><td class=`"num`">$exit</td></tr>"
                }
                $sections += "<div class=`"items`"><table><thead><tr><th>Item</th><th>State</th><th>Detail</th><th class=`"num`">Exit</th></tr></thead><tbody>$rows</tbody></table></div>"
            }
            $sections += '</div>'
        }
        $sections += '</div>'
    }

    if ($scopes.Count -eq 0) {
        $sections = '<div class="meta">No status recorded yet for this campaign. Waiting for the first update...</div>'
    }

    # ---- Metadata -----------------------------------------------------------------
    $encTitle = ConvertTo-SPSHtmlEncoded -Value $Title
    $encEnv = ConvertTo-SPSHtmlEncoded -Value $EnvName
    $encApp = ConvertTo-SPSHtmlEncoded -Value $AppCode
    $encFarm = ConvertTo-SPSHtmlEncoded -Value $FarmName
    $encVersion = ConvertTo-SPSHtmlEncoded -Value $Version
    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $metaParts = @()
    if (-not [string]::IsNullOrEmpty($encApp)) { $metaParts += "AppCode: $encApp" }
    if (-not [string]::IsNullOrEmpty($encEnv)) { $metaParts += "Environment: $encEnv" }
    if (-not [string]::IsNullOrEmpty($encFarm)) { $metaParts += "Farm: $encFarm" }
    $metaParts += "Generated: $generated"
    $metaParts += "SPSUpdate $encVersion"
    $metaLine = $metaParts -join ' &middot; '

    $effectiveRefresh = if ($Completed) { 0 } else { $RefreshSeconds }
    $liveNote = if ($effectiveRefresh -gt 0) {
        "<span class=`"live`">&#9679; live &middot; auto-refresh every ${effectiveRefresh}s</span>"
    }
    else { '<span class="meta">Campaign completed (auto-refresh off).</span>' }

    # ---- Assemble -----------------------------------------------------------------
    $html = (Get-SPSReportHtmlHead -Title $encTitle -RefreshSeconds $effectiveRefresh) +
    "<h1>$encTitle</h1>" +
    "<div class=`"meta`">$metaLine &middot; $liveNote</div>" +
    "<div class=`"summary`"><h3 style=`"margin-top:0`">Overall</h3><div class=`"cards`">$cards</div></div>" +
    $sections +
    "<div class=`"footer`">Generated by SPSUpdate $encVersion. This dashboard is assembled from the shared status store and refreshes itself while patching is in progress.</div>" +
    '</body></html>'

    $outDir = Split-Path -Path $OutputFile -Parent
    if (-not [string]::IsNullOrEmpty($outDir) -and -not (Test-Path -Path $outDir)) {
        $null = New-Item -Path $outDir -ItemType Directory -Force
    }
    # Atomic write so an open browser never reads a half-written dashboard.
    $tmpPath = '{0}.tmp.{1}' -f $OutputFile, ([guid]::NewGuid().ToString('N'))
    $encoding = New-Object System.Text.UTF8Encoding($true)
    try {
        [System.IO.File]::WriteAllText($tmpPath, $html, $encoding)
        Move-Item -Path $tmpPath -Destination $OutputFile -Force -ErrorAction Stop
    }
    catch {
        if (Test-Path -Path $tmpPath) { Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue }
        Set-Content -Path $OutputFile -Value $html -Force -Encoding UTF8
    }

    return $OutputFile
}
