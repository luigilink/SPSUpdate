# Tests for the patching status store (Set-/Get-SPSUpdateStatus, Get-SPSStatusCampaignPath).
# Cross-platform: plain JSON files on the local filesystem.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupd-status-" + [guid]::NewGuid())
    New-Item -Path $script:root -ItemType Directory -Force | Out-Null
}

AfterAll {
    if ($script:root -and (Test-Path $script:root)) {
        Remove-Item -Path $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSStatusCampaignPath' {
    It 'falls back to Results\status when StatusStorePath is empty' {
        $p = Get-SPSStatusCampaignPath -StatusStorePath '' -ResultsFolder $script:root -Application 'contoso' -Environment 'PROD' -FarmName 'CONTENT'
        $p | Should -Be (Join-Path -Path (Join-Path -Path $script:root -ChildPath 'status') -ChildPath 'contoso-PROD-CONTENT')
    }

    It 'uses the configured store path when provided' {
        $store = Join-Path -Path $script:root -ChildPath 'share'
        $p = Get-SPSStatusCampaignPath -StatusStorePath $store -ResultsFolder $script:root -Application 'contoso' -Environment 'PROD' -FarmName 'CONTENT'
        $p | Should -Be (Join-Path -Path $store -ChildPath 'contoso-PROD-CONTENT')
    }

    It 'creates the folder with -CreateIfMissing' {
        $store = Join-Path -Path $script:root -ChildPath 'make'
        $p = Get-SPSStatusCampaignPath -StatusStorePath $store -ResultsFolder $script:root -Application 'a' -Environment 'e' -FarmName 'f' -CreateIfMissing
        Test-Path $p | Should -BeTrue
    }
}

Describe 'Set-SPSUpdateStatus / Get-SPSUpdateStatus round-trip' {
    BeforeAll {
        $script:camp = Join-Path -Path $script:root -ChildPath 'campaign1'
    }

    It 'writes a scope file named <Server>__<Scope>.json' {
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Running' -Confirm:$false | Out-Null
        Test-Path (Join-Path -Path $script:camp -ChildPath 'APP1__Sequence1.json') | Should -BeTrue
    }

    It 'accumulates items across calls inside the same scope' {
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -Item 'DB_A' -ItemState 'Done' -ItemDetail 'upgraded' -ExitCode 0 -Confirm:$false | Out-Null
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -State 'Done' -Item 'DB_B' -ItemState 'Done' -ExitCode 0 -Confirm:$false | Out-Null

        $all = Get-SPSUpdateStatus -CampaignPath $script:camp
        $seq1 = $all | Where-Object { $_.Scope -eq 'Sequence1' }
        @($seq1.Items).Count | Should -Be 2
        ($seq1.Items | Where-Object Name -eq 'DB_A').State | Should -Be 'Done'
        $seq1.State | Should -Be 'Done'
    }

    It 'updates an existing item in place rather than duplicating it' {
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Sequence1' -Phase 'Upgrade' -Server 'APP1' -Item 'DB_A' -ItemState 'Warning' -ItemDetail 'retried' -Confirm:$false | Out-Null
        $seq1 = Get-SPSUpdateStatus -CampaignPath $script:camp | Where-Object { $_.Scope -eq 'Sequence1' }
        @($seq1.Items | Where-Object Name -eq 'DB_A').Count | Should -Be 1
        ($seq1.Items | Where-Object Name -eq 'DB_A').State | Should -Be 'Warning'
    }

    It 'keeps separate scopes and servers in separate files' {
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'ProductUpdate' -Phase 'ProductUpdate' -Server 'WFE1' -State 'Running' -Item 'uber.exe' -ItemState 'Running' -Confirm:$false | Out-Null
        $all = Get-SPSUpdateStatus -CampaignPath $script:camp
        ($all | Where-Object { $_.Server -eq 'WFE1' -and $_.Scope -eq 'ProductUpdate' }) | Should -Not -BeNullOrEmpty
        @($all).Count | Should -Be 2
    }

    It 'records the optional percent' {
        Set-SPSUpdateStatus -CampaignPath $script:camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Running' -Percent 50 -Confirm:$false | Out-Null
        $w = Get-SPSUpdateStatus -CampaignPath $script:camp | Where-Object { $_.Scope -eq 'Wizard' }
        $w.Percent | Should -Be 50
    }
}

Describe 'Get-SPSUpdateStatus resilience' {
    It 'returns an empty array for a missing campaign folder' {
        $missing = Join-Path -Path $script:root -ChildPath 'does-not-exist'
        @(Get-SPSUpdateStatus -CampaignPath $missing).Count | Should -Be 0
    }

    It 'ignores temporary (*.tmp.*) files' {
        $camp = Join-Path -Path $script:root -ChildPath 'campaign2'
        New-Item -Path $camp -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $camp 'APP1__Wizard.json.tmp.abc') -Value '{ broken'
        Set-SPSUpdateStatus -CampaignPath $camp -Scope 'Wizard' -Phase 'Wizard' -Server 'APP1' -State 'Done' -Confirm:$false | Out-Null
        @(Get-SPSUpdateStatus -CampaignPath $camp).Count | Should -Be 1
    }
}
