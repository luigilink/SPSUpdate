# Tests for the live patching dashboard (Export-SPSUpdateProgressReport).
# Cross-platform: server-rendered HTML from the local status store + an optional inventory JSON.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupd-dash-" + [guid]::NewGuid())
    New-Item -Path $script:root -ItemType Directory -Force | Out-Null

    function New-Campaign {
        param([string]$Name)
        $camp = Join-Path -Path $script:root -ChildPath $Name
        New-Item -Path $camp -ItemType Directory -Force | Out-Null
        return $camp
    }

    function New-Inventory {
        param([string]$Path, [switch]$WithAnomaly)
        $status1 = if ($WithAnomaly) { 'Upgrade required' } else { 'No update pending' }
        $inv = [PSCustomObject]@{
            SPContentDatabase1 = @(
                [PSCustomObject]@{ Name = 'WSS_Content_Portal'; WebAppUrl = 'https://portal'; Server = 'SINGLE-WEB-SPSSQL'; SizeInMB = 48210; UpgradeStatus = $status1 }
            )
            SPContentDatabase2 = @(
                [PSCustomObject]@{ Name = 'WSS_Content_Teams'; WebAppUrl = 'https://teams'; Server = 'SINGLE-WEB-SPSSQL'; SizeInMB = 32780; UpgradeStatus = 'No update pending' }
            )
        }
        $inv | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
        return $Path
    }
}

AfterAll {
    if ($script:root -and (Test-Path $script:root)) {
        Remove-Item -Path $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Export-SPSUpdateProgressReport (three-card dashboard)' {
    BeforeAll {
        $script:camp = New-Campaign -Name 'run'
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Role 'Application' -Build '16.0.20326.20136' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'WFE1' -State 'Running' -Role 'WebFrontEnd' -Build '16.0.17928.20286' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Done' -Role 'Application' -Build '16.0.20326.20136' -PatchStatus 'No Action Required' -Detail 'PSConfig completed successfully' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Reboot' -Phase 'Reboot' -Server 'WFE1' -State 'Pending' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -Item 'WSS_Content_Portal' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null

        $script:inv = New-Inventory -Path (Join-Path $script:camp 'inv.json')
        $script:out = Export-SPSUpdateProgressReport -CampaignPath $script:camp -EnvName 'PROD' -AppCode 'zebes' -FarmName 'CONTENT' -TargetBuild '16.0.20326.20136' -MasterServer 'APP1' -ContentDbInventoryFile $script:inv -RefreshSeconds 15
        $script:html = Get-Content -Path $script:out -Raw
    }

    It 'writes _dashboard.html in the campaign folder by default' {
        $script:out | Should -Be (Join-Path -Path $script:camp -ChildPath '_dashboard.html')
        Test-Path $script:out | Should -BeTrue
    }

    It 'renders the three cards' {
        $script:html | Should -Match 'Binaries Installation'
        $script:html | Should -Match 'SharePoint Configuration Wizard'
        $script:html | Should -Match 'Content Databases'
    }

    It 'shows the per-card columns' {
        $script:html | Should -Match '<th>Patch Status</th>'
        $script:html | Should -Match '<th>Build Version</th>'
        $script:html | Should -Match '<th>Completed Date</th>'
        $script:html | Should -Match '<th>SQL Instance</th>'
        $script:html | Should -Match '<th>Upgrade Status</th>'
    }

    It 'lists the servers with their build and patch status' {
        $script:html | Should -Match 'APP1'
        $script:html | Should -Match 'WFE1'
        $script:html | Should -Match '16.0.20326.20136'
        $script:html | Should -Match 'No Action Required'
    }

    It 'tags the master server' {
        $script:html | Should -Match 'class="master-tag">master</span>'
    }

    It 'shows a reboot-pending pill for a server with a deferred reboot' {
        $script:html | Should -Match 'pill reboot">Reboot pending'
    }

    It 'renders content databases from the inventory joined with their state' {
        $script:html | Should -Match 'WSS_Content_Portal'
        $script:html | Should -Match 'SINGLE-WEB-SPSSQL'
        $script:html | Should -Match 'No update pending'
    }

    It 'enables auto-refresh for a running campaign' {
        $script:html | Should -Match 'http-equiv="refresh" content="15"'
        $script:html | Should -Match 'auto-refresh every 15s'
    }

    It 'is self-contained (no external resources)' {
        $script:html | Should -Match '<!DOCTYPE html>'
        $script:html | Should -Not -Match 'src="http'
        $script:html | Should -Not -Match '<link'
    }
}

Describe 'Export-SPSUpdateProgressReport (completed campaign)' {
    It 'disables auto-refresh and notes completion' {
        $camp = New-Campaign -Name 'done'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -Completed
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match 'http-equiv="refresh"'
        $h | Should -Match 'campaign completed'
    }
}

Describe 'Export-SPSUpdateProgressReport (pre-patch anomaly)' {
    It 'shows an informational banner when a server is not No Action Required' {
        $camp = New-Campaign -Name 'anom'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Pending' -PatchStatus 'Upgrade Required' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'Farm inconsistency detected'
        $h | Should -Match 'not reporting'
    }

    It 'shows a database anomaly when a DB needs an upgrade before patching' {
        $camp = New-Campaign -Name 'anomdb'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Pending' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json') -WithAnomaly
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'database\(s\) with a pending upgrade'
    }

    It 'does not raise a database anomaly for an Unknown (unresolved) upgrade status' {
        $camp = New-Campaign -Name 'anomdb-unknown'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Pending' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        $invPath = Join-Path $camp 'inv.json'
        [PSCustomObject]@{
            SPContentDatabase1 = @(
                [PSCustomObject]@{ Name = 'WSS_Content_New'; WebAppUrl = 'https://portal'; Server = 'SQL1'; SizeInMB = 100; UpgradeStatus = 'Unknown' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $invPath -Encoding UTF8
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $invPath
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match 'Farm inconsistency detected'
        $h | Should -Match 'Unknown'
    }

    It 'shows an upgraded database (State Done) as up to date and raises no DB anomaly' {
        $camp = New-Campaign -Name 'db-done'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        # The DB's inventory baseline still says "Upgrade required", but SPSUpdate has upgraded it.
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json') -WithAnomaly
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -Item 'WSS_Content_Portal' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv
        $h = Get-Content -Path $out -Raw
        # The Content DB row for the done database shows No update pending, not the stale baseline.
        $h | Should -Match 'WSS_Content_Portal'
        $h | Should -Not -Match 'Upgrade required'
        # And it no longer counts as a pending-upgrade anomaly.
        $h | Should -Not -Match 'database\(s\) with a pending upgrade'
    }

    It 'does NOT mark a mount-only Done database as up to date (upgrade disabled)' {
        $camp = New-Campaign -Name 'db-mount-only'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json') -WithAnomaly
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Mount' -Server 'APP1' -Item 'WSS_Content_Portal' -ItemState 'Done' -Confirm:$false | Out-Null
        # Mount-only: the database was mounted, not upgraded, so the baseline upgrade status stands.
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv -ContentDbUpgradeEnabled:$false
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'Upgrade required'
        $h | Should -Match 'database\(s\) with a pending upgrade'
    }
}

Describe 'Export-SPSUpdateProgressReport (campaign roll-up)' {
    It 'counts a failed non-card scope (SideBySide) so the campaign is not falsely green' {
        $camp = New-Campaign -Name 'rollup-fail'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'SideBySide' -Phase 'SideBySide' -Server 'WFE1' -State 'Failed' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'Failed <span class="n">1</span>'
        $h | Should -Match 'color:var\(--err\)'
    }

    It 'counts inventory databases with no processing item yet as pending work' {
        $camp = New-Campaign -Name 'rollup-pending'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json')
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv
        $h = Get-Content -Path $out -Raw
        # 1 server done + 2 inventory databases still pending = 33% complete, 2 pending.
        $h | Should -Match 'Pending <span class="n">2</span>'
        $h | Should -Match '>33%<'
    }

    It 'reflects a failed scope whose only item is still Running (scope-level failure not hidden)' {
        $camp = New-Campaign -Name 'rollup-failitem'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Failed' -Item 'DB1' -ItemState 'Running' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'Failed <span class="n">1</span>'
        $h | Should -Match 'color:var\(--err\)'
    }

    It 'does not report 100% when a scope is still Running with all items Done' {
        $camp = New-Campaign -Name 'rollup-runscope'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Running' -Item 'DB1' -ItemState 'Done' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match '>100%<'
        $h | Should -Match 'Running <span class="n">1</span>'
    }

    It 'caps the displayed percentage at 99 until every unit is terminal' {
        $camp = New-Campaign -Name 'rollup-cap'
        1..9 | ForEach-Object {
            Set-SPSUpdateStatus -CampaignPath $camp -Scope "ProductUpdate" -Phase 'ProductUpdate' -Server "SRV$_" -State 'Done' -Confirm:$false | Out-Null
        }
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'SRV10' -State 'Running' -Confirm:$false | Out-Null
        # 9 of 10 done (90%) is below 100 anyway; add enough done units to round to 100 with one left.
        10..299 | ForEach-Object {
            Set-SPSUpdateStatus -CampaignPath $camp -Scope "ProductUpdate" -Phase 'ProductUpdate' -Server "PAD$_" -State 'Done' -Confirm:$false | Out-Null
        }
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match '>100%<'
        $h | Should -Not -Match 'color:var\(--ok\)">100%'
    }

    It 'excludes inventory databases from completion when database work is disabled' {
        $camp = New-Campaign -Name 'rollup-nodbwork'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json')
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv -ContentDbProcessingEnabled:$false
        $h = Get-Content -Path $out -Raw
        # The single server is done and databases are not counted, so the campaign is complete.
        $h | Should -Match 'color:var\(--ok\)">100%'
        # Databases are still displayed, shown as Skipped rather than Pending.
        $h | Should -Match 'WSS_Content_Portal'
        $h | Should -Match 'pill skipped'
    }
}

Describe 'Export-SPSUpdateProgressReport (card consistency)' {
    It 'shows the ProductUpdate build on the Wizard card when the farm baseline lags' {
        $camp = New-Campaign -Name 'wizbuild'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Build '16.0.20326.20136' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        # Wizard row seeded with the older farm build.
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Done' -Build '16.0.17928.20286' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        # The Wizard card must show the installed ProductUpdate build, not the stale baseline build.
        ([regex]::Matches($h, '16\.0\.20326\.20136')).Count | Should -BeGreaterThan 1
    }

    It 'reflects a failed sequence scope on its still-running database item' {
        $camp = New-Campaign -Name 'dbfail'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Failed' -Item 'WSS_Content_Portal' -ItemState 'Running' -Confirm:$false | Out-Null
        $inv = New-Inventory -Path (Join-Path $camp 'inv.json')
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -ContentDbInventoryFile $inv
        $h = Get-Content -Path $out -Raw
        # The database row for the failed scope's running item must show Failed, not Running.
        $h | Should -Match 'WSS_Content_Portal'
        $h | Should -Match '<span class="pill failed">Failed</span>'
        $h | Should -Not -Match 'WSS_Content_Portal.*pill running'
    }
}

Describe 'Export-SPSUpdateProgressReport (encoding)' {
    It 'HTML-encodes dynamic values' {
        $camp = New-Campaign -Name 'enc'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Failed' -Detail 'oops <x> & y' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'oops &lt;x&gt; &amp; y'
        $h | Should -Not -Match 'oops <x> & y'
    }
}

Describe 'Export-SPSUpdateProgressReport (reboot state visibility)' {
    It 'surfaces a failed reboot as a pill on the Binaries card (not only pending)' {
        $camp = New-Campaign -Name 'reboot-failed'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP2' -State 'Done' -Role 'Application' -Build '16.0.19725.20522' -PatchStatus 'No Action Required' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Reboot' -Phase 'Reboot' -Server 'APP2' -State 'Failed' -Detail 'Could not register the reboot-confirm task; reboot aborted' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match '<span class="pill failed">Reboot failed</span>'
    }

    It 'surfaces a completed reboot as a Rebooted pill' {
        $camp = New-Campaign -Name 'reboot-done'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'WFE1' -State 'Done' -Role 'WebFrontEnd' -Build '16.0.19725.20522' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Reboot' -Phase 'Reboot' -Server 'WFE1' -State 'Done' -Detail 'Server back online after automatic reboot' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match '<span class="pill done">Rebooted</span>'
    }

    It 'keeps a skipped reboot quiet (no reboot pill)' {
        $camp = New-Campaign -Name 'reboot-skipped'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Role 'Application' -Build '16.0.19725.20522' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Reboot' -Phase 'Reboot' -Server 'APP1' -State 'Skipped' -Detail 'No reboot required' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match 'pill failed">Reboot failed'
        $h | Should -Not -Match 'pill reboot">Reboot pending'
        $h | Should -Not -Match 'pill done">Rebooted'
    }
}

Describe 'Export-SPSUpdateProgressReport (reboot state precedence)' {
    # The reboot pills are selected from scopes filtered by Phase = 'Reboot'. When a server has
    # more than one such scope, a higher-priority state (Failed > Pending/Running > Done) must win
    # regardless of enumeration order, so a later Done can never hide a Failed reboot.
    It 'prefers Failed over Done when Done is written first' {
        $camp = New-Campaign -Name 'reboot-prec-1'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP2' -State 'Done' -Role 'Application' -Build '16.0.19725.20522' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Reboot' -Phase 'Reboot' -Server 'APP2' -State 'Done' -Detail 'Server back online' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'RebootRetry' -Phase 'Reboot' -Server 'APP2' -State 'Failed' -Detail 'Could not register the reboot-confirm task' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match '<span class="pill failed">Reboot failed</span>'
        $h | Should -Not -Match '<span class="pill done">Rebooted</span>'
    }

    It 'prefers Failed over Done when Failed is written first' {
        $camp = New-Campaign -Name 'reboot-prec-2'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP2' -State 'Done' -Role 'Application' -Build '16.0.19725.20522' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Reboot' -Phase 'Reboot' -Server 'APP2' -State 'Failed' -Detail 'Could not register the reboot-confirm task' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'RebootRetry' -Phase 'Reboot' -Server 'APP2' -State 'Done' -Detail 'Server back online' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match '<span class="pill failed">Reboot failed</span>'
        $h | Should -Not -Match '<span class="pill done">Rebooted</span>'
    }
}
