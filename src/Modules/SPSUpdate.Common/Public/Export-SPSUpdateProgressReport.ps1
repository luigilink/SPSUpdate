function Export-SPSUpdateProgressReport {
    <#
        .SYNOPSIS
        Renders the live patching dashboard (three server-oriented cards) from the status store.

        .DESCRIPTION
        Export-SPSUpdateProgressReport reads every status scope of a campaign (via
        Get-SPSUpdateStatus) and renders a single, self-contained HTML dashboard organised as
        three cards:
          1. Binaries Installation - one row per farm server (Status, Patch Status, Build, Completed).
          2. SharePoint Configuration Wizard - one row per farm server (+ Detail).
          3. Content Databases - one row per content database, joined from the optional
             ContentDatabase inventory JSON and the per-database processing state.

        It is regenerated periodically by the master during the run and carries a meta-refresh so
        an open browser updates on its own. Fully server-rendered (no fetch), works over file:// or
        HTTP. All values are HTML-encoded. Returns the path of the dashboard that was written.

        .PARAMETER CampaignPath
        Folder of the patching campaign to read (status files live here; the dashboard is written
        here by default).

        .PARAMETER OutputFile
        Destination path of the dashboard. Defaults to '_dashboard.html' in CampaignPath.

        .PARAMETER Title
        Heading shown at the top. Defaults to a generic title.

        .PARAMETER EnvName
        Environment label shown in the header chips.

        .PARAMETER AppCode
        Application code shown in the header chips.

        .PARAMETER FarmName
        Farm label shown in the header chips.

        .PARAMETER TargetBuild
        Optional target build shown in the header chips.

        .PARAMETER MasterServer
        Optional master/orchestrator server name; tagged "master" in the cards.

        .PARAMETER ContentDbInventoryFile
        Optional path to the ContentDatabase inventory JSON (as produced by
        Initialize-SPSContentDbJsonFile). When provided, the Content Databases card is populated
        from it, joined with the per-database processing state in the status store.

        .PARAMETER ContentDbProcessingEnabled
        Whether the campaign actually mounts/upgrades content databases. When $false (both
        MountContentDatabase and UpgradeContentDatabase disabled), the inventory is still displayed
        but its not-yet-processed databases are shown as Skipped and excluded from the completion
        roll-up, so a campaign that legitimately skips database work can still reach 100%. Default
        $true.

        .PARAMETER ContentDbUpgradeEnabled
        Whether the campaign upgrades content databases (UpgradeContentDatabase). When $true, a
        database marked Done has actually been upgraded, so its upgrade status is shown as up to
        date regardless of the inventory baseline. When $false (a mount-only campaign), a Done
        database was only mounted, not upgraded, so the override does not apply. Default $true.

        .PARAMETER RefreshSeconds
        Meta-refresh interval (seconds). 0 disables auto-refresh. Default 15.

        .PARAMETER Completed
        Mark the campaign as completed: disables the auto-refresh and shows a final state.

        .PARAMETER Version
        SPSUpdate version stamped in the footer. Defaults to the module version.

        .EXAMPLE
        Export-SPSUpdateProgressReport -CampaignPath $c -EnvName 'PROD' -AppCode 'contoso' -FarmName 'CONTENT'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MasterServer',
        Justification = 'Used inside the $serverCell script block to tag the master/orchestrator server.')]
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
        [System.String]
        $TargetBuild,

        [Parameter()]
        [System.String]
        $MasterServer,

        [Parameter()]
        [System.String]
        $ContentDbInventoryFile,

        [Parameter()]
        [System.Boolean]
        $ContentDbProcessingEnabled = $true,

        [Parameter()]
        [System.Boolean]
        $ContentDbUpgradeEnabled = $true,

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
    if ([string]::IsNullOrEmpty($Title)) { $Title = 'SharePoint Server Update' }
    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = (Get-Module -Name SPSUpdate.Common -ErrorAction SilentlyContinue).Version
        $Version = if ($null -ne $moduleVersion) { $moduleVersion.ToString() } else { 'unknown' }
    }

    $scopes = @(Get-SPSUpdateStatus -CampaignPath $CampaignPath)

    # ---- helpers ------------------------------------------------------------------
    $enc = { param($v) ConvertTo-SPSHtmlEncoded -Value "$v" }
    $pill = {
        param($state)
        $s = if ([string]::IsNullOrEmpty($state)) { 'Pending' } else { "$state" }
        $cls = switch ($s) {
            'Done' { 'done' } 'Running' { 'running' } 'Failed' { 'failed' }
            'Skipped' { 'skipped' } 'Reboot' { 'reboot' } default { 'pending' }
        }
        "<span class=`"pill $cls`">$(& $enc $s)</span>"
    }
    $fmtDate = {
        param($iso)
        if ([string]::IsNullOrWhiteSpace("$iso")) { return '&mdash;' }
        try { return (Get-Date -Date $iso -Format 'yyyy-MM-dd HH:mm:ss') } catch { return (& $enc $iso) }
    }
    $orDash = { param($v) if ([string]::IsNullOrWhiteSpace("$v")) { '&mdash;' } else { & $enc $v } }
    $roleSub = { param($role) if ([string]::IsNullOrWhiteSpace("$role")) { '' } else { "<div class=`"sub2`">$(& $enc $role)</div>" } }
    $serverCell = {
        param($server, $role)
        $tag = if ($MasterServer -and "$server" -eq "$MasterServer") { '<span class="master-tag">master</span>' } else { '' }
        "<span class=`"srv`">$(& $enc $server)</span>$tag$(& $roleSub $role)"
    }

    # ---- partition scopes ---------------------------------------------------------
    $binaries = @($scopes | Where-Object { $_.Phase -eq 'ProductUpdate' } | Sort-Object Server)
    $wizard = @($scopes | Where-Object { $_.Phase -eq 'Wizard' } | Sort-Object Server)
    $rebootScopes = @($scopes | Where-Object { $_.Phase -eq 'Reboot' })
    $dbScopes = @($scopes | Where-Object { $_.Phase -eq 'Mount' -or $_.Phase -eq 'Upgrade' -or $_.Phase -eq 'Sequence' })

    # A server has a pending/running reboot?
    $rebootPendingServers = @($rebootScopes | Where-Object { $_.State -eq 'Pending' -or $_.State -eq 'Running' } | Select-Object -ExpandProperty Server -Unique)

    # ---- Card 1: Binaries Installation --------------------------------------------
    $binRows = foreach ($b in $binaries) {
        $rebootPill = if ($rebootPendingServers -contains $b.Server) { ' <span class="pill reboot">Reboot pending</span>' } else { '' }
        '<tr>' +
        "<td>$(& $serverCell $b.Server $b.Role)</td>" +
        "<td>$(& $pill $b.State)$rebootPill</td>" +
        "<td>$(& $orDash $b.PatchStatus)</td>" +
        "<td class=`"mono`">$(& $orDash $b.Build)</td>" +
        "<td class=`"mono`">$(& $fmtDate $b.CompletedAt)</td>" +
        '</tr>'
    }
    if (-not $binRows) { $binRows = '<tr><td colspan="5" class="muted-txt">No server status yet.</td></tr>' }

    # ---- Card 2: SharePoint Configuration Wizard ----------------------------------
    # The Wizard row's build is seeded from the farm build at baseline, which can still be the
    # previous CU until PSConfig runs. Prefer the same server's ProductUpdate-recorded build (the
    # actually installed CU) when available, so both cards agree on the installed version.
    $puBuildByServer = @{}
    foreach ($b in $binaries) {
        if (-not [string]::IsNullOrWhiteSpace("$($b.Build)")) { $puBuildByServer["$($b.Server)"] = "$($b.Build)" }
    }
    $wizRows = foreach ($w in $wizard) {
        $wizBuild = if ($puBuildByServer.ContainsKey("$($w.Server)")) { $puBuildByServer["$($w.Server)"] } else { $w.Build }
        '<tr>' +
        "<td>$(& $serverCell $w.Server $w.Role)</td>" +
        "<td>$(& $pill $w.State)</td>" +
        "<td>$(& $orDash $w.PatchStatus)</td>" +
        "<td class=`"mono`">$(& $orDash $wizBuild)</td>" +
        "<td class=`"mono`">$(& $fmtDate $w.CompletedAt)</td>" +
        "<td>$(& $orDash $w.Detail)</td>" +
        '</tr>'
    }
    if (-not $wizRows) { $wizRows = '<tr><td colspan="6" class="muted-txt">No wizard status yet.</td></tr>' }

    # ---- Card 3: Content Databases ------------------------------------------------
    # Build a per-database processing state lookup from the sequence/mount/upgrade items. When a
    # sequence scope failed, its still-active (Running/Pending) item is reflected as Failed - the
    # sequence handler marks only the scope on error and leaves the item Running - while completed
    # items keep their terminal state.
    $dbStateByName = @{}
    foreach ($sc in $dbScopes) {
        $scopeFailed = ("$($sc.State)" -eq 'Failed')
        foreach ($it in @($sc.Items)) {
            if ($null -ne $it -and -not [string]::IsNullOrEmpty("$($it.Name)")) {
                $itState = "$($it.State)"
                if ($scopeFailed -and ($itState -eq 'Running' -or $itState -eq 'Pending')) { $itState = 'Failed' }
                $dbStateByName["$($it.Name)".ToLowerInvariant()] = $itState
            }
        }
    }

    $dbRows = @()
    $dbCount = 0
    $dbUpgrading = 0
    $dbInvNames = @{}
    $inventory = $null
    if (-not [string]::IsNullOrWhiteSpace($ContentDbInventoryFile) -and (Test-Path -Path $ContentDbInventoryFile)) {
        try { $inventory = Get-Content -Path $ContentDbInventoryFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $inventory = $null }
    }
    if ($null -ne $inventory) {
        $seqProps = @('SPContentDatabase1', 'SPContentDatabase2', 'SPContentDatabase3', 'SPContentDatabase4')
        for ($s = 0; $s -lt $seqProps.Count; $s++) {
            $prop = $seqProps[$s]
            if ($inventory.PSObject.Properties.Name -notcontains $prop) { continue }
            foreach ($db in @($inventory.$prop)) {
                if ($null -eq $db -or [string]::IsNullOrEmpty("$($db.Name)")) { continue }
                $dbCount++
                $dbNameKey = "$($db.Name)".ToLowerInvariant()
                $dbInvNames[$dbNameKey] = $true
                $size = ''
                if ($db.PSObject.Properties.Name -contains 'SizeInMB' -and "$($db.SizeInMB)" -ne '') {
                    $size = '{0:N0}' -f ([double]$db.SizeInMB)
                }
                $upgradeStatus = if ($db.PSObject.Properties.Name -contains 'UpgradeStatus' -and "$($db.UpgradeStatus)" -ne '') { "$($db.UpgradeStatus)" } else { '' }
                $state = $dbStateByName["$($db.Name)".ToLowerInvariant()]
                if ([string]::IsNullOrEmpty($state)) {
                    # No processing record yet: Pending when database work is planned, otherwise
                    # Skipped (this campaign does not mount/upgrade content databases).
                    $state = if ($ContentDbProcessingEnabled) { 'Pending' } else { 'Skipped' }
                }
                # Safety net: a database that SPSUpdate has actually UPGRADED (State Done while
                # content-database upgrade is enabled) is up to date, so show "No update pending"
                # even if the inventory snapshot still carries an older "Upgrade available" baseline.
                # A mount-only campaign (upgrade disabled) marks a database Done after mounting
                # WITHOUT upgrading it, so the override must not apply there.
                if ($state -eq 'Done' -and $ContentDbUpgradeEnabled) { $upgradeStatus = 'No update pending' }
                if ($state -eq 'Running') { $dbUpgrading++ }
                $dbRows += '<tr>' +
                "<td class=`"mono`">$(& $enc $db.Name)</td>" +
                "<td>$(& $orDash $db.WebAppUrl)</td>" +
                "<td class=`"mono`">$(& $orDash $db.Server)</td>" +
                "<td class=`"num`">$(if ($size -ne '') { $size } else { '&mdash;' })</td>" +
                "<td>Sequence $($s + 1)</td>" +
                "<td>$(& $orDash $upgradeStatus)</td>" +
                "<td>$(& $pill $state)</td>" +
                '</tr>'
            }
        }
    }
    if (-not $dbRows -or $dbRows.Count -eq 0) {
        $dbRows = @('<tr><td colspan="7" class="muted-txt">No content database inventory for this campaign.</td></tr>')
    }

    # ---- Summary roll-up (every scope contributes leaf units so no failure is hidden) ---
    # A scope with named items contributes one unit per item; otherwise the scope itself is one
    # unit. This covers the server cards (ProductUpdate/Wizard), the content-database items and
    # ALSO the Reboot / SideBySide / sequence-level scopes that have no card, so a failed campaign
    # step can never be rolled up as green 100%. A scope-level Failed/Running state is tracked even
    # when the scope has items (the exception handlers mark only the scope, not its items), so an
    # all-Done item set under a Failed or still-Running scope never shows as green 100%.
    $units = @()
    $recordedDbNames = @{}
    foreach ($sc in $scopes) {
        $named = @($sc.Items | Where-Object { $_ -and "$($_.Name)" -ne '' })
        if ($named.Count -gt 0) {
            $itemStates = @()
            foreach ($it in $named) {
                $itemStates += "$($it.State)"
                $units += "$($it.State)"
                if ($sc.Phase -eq 'Mount' -or $sc.Phase -eq 'Upgrade' -or $sc.Phase -eq 'Sequence') {
                    $recordedDbNames["$($it.Name)".ToLowerInvariant()] = $true
                }
            }
            # Reflect a scope-level state that the items do not already express, without
            # double-counting completed leaf work.
            $scState = "$($sc.State)"
            if ($scState -eq 'Failed' -and ($itemStates -notcontains 'Failed')) {
                $units += 'Failed'
            }
            elseif ($scState -eq 'Running' -and -not ($itemStates | Where-Object { $_ -eq 'Running' -or $_ -eq 'Pending' })) {
                # Scope still running but every known item is terminal: keep it off 100%.
                $units += 'Running'
            }
        }
        else {
            $units += "$($sc.State)"
        }
    }
    # Content databases from the inventory that have no processing item yet: when database work is
    # planned they are still pending work (counted so completion reflects the whole farm and cannot
    # reach 100% with rows pending). When database work is disabled for this campaign they are not
    # counted at all, so a campaign that legitimately skips database work can still reach 100%.
    if ($ContentDbProcessingEnabled) {
        foreach ($nm in $dbInvNames.Keys) {
            if (-not $recordedDbNames.ContainsKey($nm)) { $units += 'Pending' }
        }
    }
    $total = $units.Count
    $countDone = @($units | Where-Object { $_ -eq 'Done' -or $_ -eq 'Skipped' }).Count
    $countRunning = @($units | Where-Object { $_ -eq 'Running' }).Count
    $countFailed = @($units | Where-Object { $_ -eq 'Failed' }).Count
    $countPending = $total - $countDone - $countRunning - $countFailed
    if ($countPending -lt 0) { $countPending = 0 }
    # Reserve 100% (and the green colour) for a campaign where every unit is Done/Skipped. Otherwise
    # cap the displayed percentage at 99 so rounding (e.g. 299/300 = 99.67 -> 100) never shows a
    # green 100% while any unit is still Pending/Running.
    $allComplete = ($total -gt 0 -and $countDone -eq $total)
    $pct = if ($total -gt 0) { [int]([math]::Round($countDone / $total * 100, 0)) } else { 0 }
    if ($pct -ge 100 -and -not $allComplete) { $pct = 99 }
    $donePctSeg = if ($total -gt 0) { [math]::Round($countDone / $total * 100, 2) } else { 0 }
    $runPctSeg = if ($total -gt 0) { [math]::Round($countRunning / $total * 100, 2) } else { 0 }
    $pctColor = if ($countFailed -gt 0) { 'var(--err)' } elseif ($allComplete) { 'var(--ok)' } else { 'var(--primary)' }

    $serverCount = @(@($binaries.Server) + @($wizard.Server) | Select-Object -Unique).Count
    $binDone = @($binaries | Where-Object { $_.State -eq 'Done' -or $_.State -eq 'Skipped' }).Count
    $wizDone = @($wizard | Where-Object { $_.State -eq 'Done' -or $_.State -eq 'Skipped' }).Count
    $rebootPendingCount = @($rebootPendingServers).Count

    # ---- Anomaly detection (informational only) -----------------------------------
    $svrAnom = @($binaries + $wizard | Where-Object {
            -not [string]::IsNullOrWhiteSpace("$($_.PatchStatus)") -and "$($_.PatchStatus)" -ne 'No Action Required'
        } | Select-Object -ExpandProperty Server -Unique)
    $dbAnom = 0
    if ($null -ne $inventory) {
        foreach ($prop in @('SPContentDatabase1', 'SPContentDatabase2', 'SPContentDatabase3', 'SPContentDatabase4')) {
            if ($inventory.PSObject.Properties.Name -notcontains $prop) { continue }
            foreach ($db in @($inventory.$prop)) {
                if ($null -eq $db) { continue }
                $us = if ($db.PSObject.Properties.Name -contains 'UpgradeStatus') { "$($db.UpgradeStatus)" } else { '' }
                # A database SPSUpdate has actually upgraded (State Done while upgrade is enabled) is
                # not a pending-upgrade anomaly even if the inventory baseline still says otherwise.
                $dbState = $dbStateByName["$($db.Name)".ToLowerInvariant()]
                if ("$dbState" -eq 'Done' -and $ContentDbUpgradeEnabled) { continue }
                # Count only a confirmed pending upgrade. 'Unknown' (a database that could not be
                # resolved live, e.g. not yet mounted) is neither healthy nor a confirmed anomaly.
                if (-not [string]::IsNullOrWhiteSpace($us) -and $us -ne 'No update pending' -and $us -ne 'Unknown') { $dbAnom++ }
            }
        }
    }
    $alertHtml = ''
    if (@($svrAnom).Count -gt 0 -or $dbAnom -gt 0) {
        $parts = @()
        if (@($svrAnom).Count -gt 0) { $parts += "$(@($svrAnom).Count) server(s) not reporting 'No Action Required'" }
        if ($dbAnom -gt 0) { $parts += "$dbAnom database(s) with a pending upgrade" }
        $alertHtml = '<div class="alert"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>' +
        "<div><strong>Farm inconsistency detected.</strong> $(& $enc ($parts -join '; ')). Review the farm state in Central Administration; this is informational and does not block the run.</div></div>"
    }

    # ---- Header metadata ----------------------------------------------------------
    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $chips = @()
    if (-not [string]::IsNullOrEmpty($EnvName)) { $chips += "<span class=`"chip`">Environment <b>$(& $enc $EnvName)</b></span>" }
    if (-not [string]::IsNullOrEmpty($FarmName)) { $chips += "<span class=`"chip`">Farm <b>$(& $enc $FarmName)</b></span>" }
    if (-not [string]::IsNullOrEmpty($AppCode)) { $chips += "<span class=`"chip`">App <b>$(& $enc $AppCode)</b></span>" }
    if (-not [string]::IsNullOrEmpty($TargetBuild)) { $chips += "<span class=`"chip`">Target build <b>$(& $enc $TargetBuild)</b></span>" }
    $chips += "<span class=`"chip`">Updated <b>$generated</b></span>"
    $chipsHtml = $chips -join ''

    $effectiveRefresh = if ($Completed) { 0 } else { $RefreshSeconds }
    $liveNote = if ($effectiveRefresh -gt 0) { "auto-refresh every ${effectiveRefresh}s" } else { 'campaign completed (auto-refresh off)' }
    $encVersion = & $enc $Version

    # ---- Assemble -----------------------------------------------------------------
    $html = (Get-SPSReportHtmlHead -Title (& $enc $Title) -RefreshSeconds $effectiveRefresh) +
    '<header class="page">' +
    '<button class="theme-toggle" onclick="var h=document.documentElement;var n=h.dataset.theme===''dark''?''light'':''dark'';h.dataset.theme=n;try{localStorage.setItem(''spsupdate-theme'',n);}catch(e){}">Theme</button>' +
    '<p class="eyebrow">SPSUpdate &middot; Patching Dashboard</p>' +
    "<h1>$(& $enc $Title)</h1>" +
    '<p class="sub">Near real-time view of the current cumulative-update campaign across the farm.</p>' +
    "<div class=`"meta-chips`">$chipsHtml</div>" +
    '</header>' +
    $alertHtml +
    '<div class="grid-top">' +
    '<div class="card summary-card"><div class="donut-wrap">' +
    '<svg viewBox="0 0 36 36" width="148" height="148">' +
    '<circle cx="18" cy="18" r="15.915" fill="none" stroke="var(--card-2)" stroke-width="3.2" pathLength="100"></circle>' +
    "<circle cx=`"18`" cy=`"18`" r=`"15.915`" fill=`"none`" stroke=`"var(--ok)`" stroke-width=`"3.2`" pathLength=`"100`" stroke-dasharray=`"$donePctSeg 100`" stroke-dashoffset=`"0`" stroke-linecap=`"round`" transform=`"rotate(-90 18 18)`"></circle>" +
    "<circle cx=`"18`" cy=`"18`" r=`"15.915`" fill=`"none`" stroke=`"var(--info)`" stroke-width=`"3.2`" pathLength=`"100`" stroke-dasharray=`"$runPctSeg 100`" stroke-dashoffset=`"-$donePctSeg`" stroke-linecap=`"round`" transform=`"rotate(-90 18 18)`"></circle>" +
    '</svg>' +
    "<div class=`"center`"><div class=`"pct`" style=`"color:$pctColor`">$pct%</div><div class=`"pct-label`">Complete</div></div>" +
    '</div><div class="legend">' +
    "<div class=`"row`"><span class=`"dot`" style=`"background:var(--ok)`"></span> Done / Skipped <span class=`"n`">$countDone</span></div>" +
    "<div class=`"row`"><span class=`"dot`" style=`"background:var(--info)`"></span> Running <span class=`"n`">$countRunning</span></div>" +
    "<div class=`"row`"><span class=`"dot`" style=`"background:var(--muted)`"></span> Pending <span class=`"n`">$countPending</span></div>" +
    "<div class=`"row`"><span class=`"dot`" style=`"background:var(--err)`"></span> Failed <span class=`"n`">$countFailed</span></div>" +
    '</div></div>' +
    '<div class="card kpis">' +
    "<div class=`"kpi total`"><div class=`"val`">$serverCount</div><div class=`"lbl`">Servers</div></div>" +
    "<div class=`"kpi ok`"><div class=`"val`">$binDone</div><div class=`"lbl`">Binaries done</div></div>" +
    "<div class=`"kpi ok`"><div class=`"val`">$wizDone</div><div class=`"lbl`">Wizard done</div></div>" +
    "<div class=`"kpi warn`"><div class=`"val`">$rebootPendingCount</div><div class=`"lbl`">Reboot pending</div></div>" +
    '</div></div>' +
    # Card 1
    '<div class="card phase-card"><div class="phase-head">' +
    '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>' +
    "<h2>Binaries Installation</h2><span class=`"count`">$(@($binaries).Count) servers</span></div>" +
    '<div class="table-wrap"><table class="grid"><thead><tr><th>Server</th><th>Status</th><th>Patch Status</th><th>Build Version</th><th>Completed Date</th></tr></thead><tbody>' +
    ($binRows -join '') + '</tbody></table></div></div>' +
    # Card 2
    '<div class="card phase-card"><div class="phase-head">' +
    '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>' +
    "<h2>SharePoint Configuration Wizard</h2><span class=`"count`">$(@($wizard).Count) servers</span></div>" +
    '<div class="table-wrap"><table class="grid"><thead><tr><th>Server</th><th>Status</th><th>Patch Status</th><th>Build Version</th><th>Completed Date</th><th>Detail</th></tr></thead><tbody>' +
    ($wizRows -join '') + '</tbody></table></div></div>' +
    # Card 3
    '<div class="card phase-card"><div class="phase-head">' +
    '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5"/><path d="M3 12a9 3 0 0 0 18 0"/></svg>' +
    "<h2>Content Databases</h2><span class=`"count`">$dbCount databases$(if ($dbUpgrading -gt 0) { " &middot; $dbUpgrading upgrading" })</span></div>" +
    '<div class="table-wrap"><table class="grid"><thead><tr><th>DB Name</th><th>Web Application</th><th>SQL Instance</th><th class="num">Size (MB)</th><th>Sequence</th><th>Upgrade Status</th><th>State</th></tr></thead><tbody>' +
    ($dbRows -join '') + '</tbody></table></div></div>' +
    "<div class=`"footer`">SPSUpdate $encVersion &middot; generated $generated &middot; $liveNote &middot; <a href=`"https://spjc.fr`">spjc.fr</a></div>" +
    '</div></body></html>'

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
