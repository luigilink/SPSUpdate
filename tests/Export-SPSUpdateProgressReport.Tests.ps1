# Tests for the live patching dashboard (Export-SPSUpdateProgressReport).
# Cross-platform: server-rendered HTML from the local status store.

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
}

AfterAll {
    if ($script:root -and (Test-Path $script:root)) {
        Remove-Item -Path $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Export-SPSUpdateProgressReport (running campaign)' {
    BeforeAll {
        $script:camp = New-Campaign -Name 'run'
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Item 'uber.exe' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'WFE1' -State 'Running' -Item 'uber.exe' -ItemState 'Running' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Running' -Percent 50 -Item 'DB_A' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null

        $script:out = Export-SPSUpdateProgressReport -CampaignPath $script:camp -EnvName 'PROD' -AppCode 'zebes' -FarmName 'CONTENT' -RefreshSeconds 15
        $script:html = Get-Content -Path $script:out -Raw
    }

    It 'writes _dashboard.html in the campaign folder by default' {
        $script:out | Should -Be (Join-Path -Path $script:camp -ChildPath '_dashboard.html')
        Test-Path $script:out | Should -BeTrue
    }

    It 'emits a meta-refresh while running' {
        $script:html | Should -Match 'http-equiv="refresh" content="15"'
        $script:html | Should -Match 'auto-refresh every 15s'
    }

    It 'shows an overall Running state' {
        $script:html | Should -Match 'class="badge Running"'
        $script:html | Should -Match 'Overall state'
    }

    It 'groups the phases and lists the servers/items' {
        $script:html | Should -Match 'Product update'
        $script:html | Should -Match 'Content database upgrade'
        $script:html | Should -Match 'APP1'
        $script:html | Should -Match 'WFE1'
        $script:html | Should -Match 'DB_A'
        $script:html | Should -Match '50%'
    }

    It 'is a self-contained document with no external resources' {
        $script:html | Should -Match '<!DOCTYPE html>'
        $script:html | Should -Not -Match 'src="http'
        $script:html | Should -Not -Match 'href="http'
    }
}

Describe 'Export-SPSUpdateProgressReport (roll-up counts each unit once)' {
    It 'does not double-count a scope and its single item' {
        $camp = New-Campaign -Name 'count'
        # Two servers, each a ProductUpdate scope with exactly one binary item, all Done.
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'APP1' -State 'Done' -Item 'uber.exe' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'SCH1' -State 'Done' -Item 'uber.exe' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null
        $h = Get-Content -Path (Export-SPSUpdateProgressReport -CampaignPath $camp) -Raw
        # The 'Done' card must read 2 (one per server), not 4 (scope + item per server).
        $h | Should -Match '<div class="card-value">2</div><div class="card-label">Done</div>'
    }

    It 'counts an item-less scope (wizard) once via its scope state' {
        $camp = New-Campaign -Name 'count-wizard'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'SCH1' -State 'Done' -Confirm:$false | Out-Null
        $h = Get-Content -Path (Export-SPSUpdateProgressReport -CampaignPath $camp) -Raw
        $h | Should -Match '<div class="card-value">2</div><div class="card-label">Done</div>'
    }
}

Describe 'Export-SPSUpdateProgressReport (states)' {
    It 'reports Failed overall when any item failed' {
        $camp = New-Campaign -Name 'fail'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Failed' -Item 'DB_X' -ItemState 'Failed' -ItemDetail 'boom' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        $h = Get-Content -Path $out -Raw
        $h | Should -Match 'class="badge Failed"'
    }

    It 'disables auto-refresh and reports Done when -Completed' {
        $camp = New-Campaign -Name 'done'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp -Completed
        $h = Get-Content -Path $out -Raw
        $h | Should -Not -Match 'http-equiv="refresh"'
        $h | Should -Match 'Campaign completed'
    }

    It 'renders a waiting message for an empty campaign' {
        $camp = New-Campaign -Name 'empty'
        $out = Export-SPSUpdateProgressReport -CampaignPath $camp
        (Get-Content -Path $out -Raw) | Should -Match 'No status recorded yet'
    }

    It 'HTML-encodes values coming from the status store' {
        $camp = New-Campaign -Name 'enc'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Running' -Item 'DB <x> & y' -ItemState 'Running' -Confirm:$false | Out-Null
        $h = Get-Content -Path (Export-SPSUpdateProgressReport -CampaignPath $camp) -Raw
        $h | Should -Match 'DB &lt;x&gt; &amp; y'
        $h | Should -Not -Match 'DB <x> & y'
    }
}
