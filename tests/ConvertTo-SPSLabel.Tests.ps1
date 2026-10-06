# Tests for the dashboard label helpers (ConvertTo-SPSPatchStatusLabel / ConvertTo-SPSRoleLabel).
# Pure string mapping from the raw SharePoint enum values to short readable dashboard labels.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-SPSPatchStatusLabel' {
    It 'maps <Raw> to <Label>' -TestCases @(
        @{ Raw = 'NoActionRequired'; Label = 'No Action Required' }
        @{ Raw = 'InstallRequired'; Label = 'Installation Required' }
        @{ Raw = 'UpgradeAvailable'; Label = 'Upgrade Available' }
        @{ Raw = 'UpgradeRequired'; Label = 'Upgrade Required' }
        @{ Raw = 'UpgradeBlocked'; Label = 'Upgrade Blocked' }
        @{ Raw = 'UpgradeInProgress'; Label = 'Upgrade in Progress' }
    ) {
        param($Raw, $Label)
        ConvertTo-SPSPatchStatusLabel -Status $Raw | Should -Be $Label
    }

    It 'is idempotent (an already-friendly label is returned unchanged)' {
        ConvertTo-SPSPatchStatusLabel -Status 'No Action Required' | Should -Be 'No Action Required'
    }

    It 'returns an empty string for empty or whitespace input' {
        ConvertTo-SPSPatchStatusLabel -Status '' | Should -Be ''
        ConvertTo-SPSPatchStatusLabel -Status '   ' | Should -Be ''
    }

    It 'returns an unknown value unchanged (trimmed)' {
        ConvertTo-SPSPatchStatusLabel -Status '  SomethingElse  ' | Should -Be 'SomethingElse'
    }

    It 'accepts pipeline input' {
        'UpgradeRequired' | ConvertTo-SPSPatchStatusLabel | Should -Be 'Upgrade Required'
    }
}

Describe 'ConvertTo-SPSRoleLabel' {
    It 'maps <Raw> to <Label>' -TestCases @(
        @{ Raw = 'Application'; Label = 'Application' }
        @{ Raw = 'ApplicationWithSearch'; Label = 'Application with Search' }
        @{ Raw = 'WebFrontEnd'; Label = 'Front-end' }
        @{ Raw = 'WebFrontEndWithDistributedCache'; Label = 'Front-end with Distributed Cache' }
        @{ Raw = 'DistributedCache'; Label = 'Distributed Cache' }
        @{ Raw = 'Search'; Label = 'Search' }
        @{ Raw = 'SingleServerFarm'; Label = 'Single-Server Farm' }
        @{ Raw = 'Custom'; Label = 'Custom' }
    ) {
        param($Raw, $Label)
        ConvertTo-SPSRoleLabel -Role $Raw | Should -Be $Label
    }

    It 'returns an empty string for empty input' {
        ConvertTo-SPSRoleLabel -Role '' | Should -Be ''
    }

    It 'returns an unknown role unchanged' {
        ConvertTo-SPSRoleLabel -Role 'FutureRole' | Should -Be 'FutureRole'
    }
}
