# Behavioural tests for Test-SPSPendingReboot. The registry probes (Test-Path,
# Get-ItemProperty, Get-ChildItem) are mocked in the module scope so the reason
# aggregation logic can be verified cross-platform.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Test-SPSPendingReboot' {
    It 'reports no pending reboot when nothing is flagged' {
        Mock -CommandName Test-Path -ModuleName SPSUpdate.Common -MockWith { $false }
        Mock -CommandName Get-ChildItem -ModuleName SPSUpdate.Common -MockWith { @() }
        Mock -CommandName Get-ItemProperty -ModuleName SPSUpdate.Common -MockWith { $null }

        $result = Test-SPSPendingReboot
        $result.IsPending | Should -BeFalse
        @($result.Reasons).Count | Should -Be 0
    }

    It 'flags a Windows Update reboot from the registry marker' {
        Mock -CommandName Get-ChildItem -ModuleName SPSUpdate.Common -MockWith { @() }
        Mock -CommandName Get-ItemProperty -ModuleName SPSUpdate.Common -MockWith { $null }
        Mock -CommandName Test-Path -ModuleName SPSUpdate.Common -MockWith { $false }
        Mock -CommandName Test-Path -ModuleName SPSUpdate.Common -MockWith { $true } -ParameterFilter {
            $Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        }

        $result = Test-SPSPendingReboot
        $result.IsPending | Should -BeTrue
        $result.Reasons | Should -Contain 'WindowsUpdateRebootRequired'
    }

    It 'flags a pending file rename operation' {
        Mock -CommandName Test-Path -ModuleName SPSUpdate.Common -MockWith { $false }
        Mock -CommandName Get-ChildItem -ModuleName SPSUpdate.Common -MockWith { @() }
        Mock -CommandName Get-ItemProperty -ModuleName SPSUpdate.Common -MockWith { $null }
        Mock -CommandName Get-ItemProperty -ModuleName SPSUpdate.Common -MockWith {
            [PSCustomObject]@{ PendingFileRenameOperations = @('\??\C:\a', '\??\C:\b') }
        } -ParameterFilter { $Path -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' }

        $result = Test-SPSPendingReboot
        $result.IsPending | Should -BeTrue
        $result.Reasons | Should -Contain 'PendingFileRenameOperations'
    }
}
