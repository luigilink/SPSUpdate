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
        $h | Should -Match 'Pre-patch inconsistency detected'
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
