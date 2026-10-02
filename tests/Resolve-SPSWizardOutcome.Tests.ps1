# Behavioural tests for Resolve-SPSWizardOutcome.
# Cross-platform by design (no SharePoint dependency): the authoritative patch status is
# injected via -PatchStatus, so these run on pwsh 7 / macOS locally and on windows-latest.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSWizardOutcome' {
    Context 'Successful exit codes' {
        It 'returns Done for exit code 0' {
            $result = Resolve-SPSWizardOutcome -ExitCode 0 -Server 'APP01'
            $result.State | Should -Be 'Done'
            $result.ExitCode | Should -Be 0
            $result.Detail | Should -Be 'PSConfig completed (exit 0)'
        }

        It 'returns Done with a generic detail when no exit code is available' {
            $result = Resolve-SPSWizardOutcome -ExitCode $null -Server 'APP01'
            $result.State | Should -Be 'Done'
            $result.Detail | Should -Be 'PSConfig completed'
        }

        It 'uses the last integer when an array of pipeline output is passed' {
            $result = Resolve-SPSWizardOutcome -ExitCode @('some text', 0) -Server 'APP01'
            $result.State | Should -Be 'Done'
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'Non-zero exit code but the upgrade actually completed' {
        It 'returns Done when the server reports NoActionRequired' {
            $result = Resolve-SPSWizardOutcome -ExitCode (-1) -Server 'WB800APP10125' -PatchStatus 'NoActionRequired'
            $result.State | Should -Be 'Done'
            $result.ExitCode | Should -Be -1
            $result.Detail | Should -Match 'NoActionRequired'
            $result.Detail | Should -Match 'exit -1'
        }

        It 'emits a warning when downgrading a non-zero exit to Done' {
            $warnings = $null
            Resolve-SPSWizardOutcome -ExitCode (-1) -Server 'APP01' -PatchStatus 'NoActionRequired' -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Genuine failures' {
        It 'returns Failed when the exit code is non-zero and action is still required' {
            $result = Resolve-SPSWizardOutcome -ExitCode (-1) -Server 'APP01' -PatchStatus 'UpgradeRequired'
            $result.State | Should -Be 'Failed'
            $result.ExitCode | Should -Be -1
            $result.Detail | Should -Match 'still requires action'
            $result.Detail | Should -Match 'https://aka.ms/installerrorcodes'
        }

        It 'returns Failed for a non-zero exit with an unknown/empty patch status' {
            $result = Resolve-SPSWizardOutcome -ExitCode 3 -Server 'APP01' -PatchStatus $null
            $result.State | Should -Be 'Failed'
            $result.ExitCode | Should -Be 3
        }
    }

    Context 'Authoritative status lookup' {
        It 'queries Get-SPSServersPatchStatus when PatchStatus is not injected' {
            Mock -CommandName Get-SPSServersPatchStatus -ModuleName SPSUpdate.Common -MockWith { 'NoActionRequired' }
            $result = Resolve-SPSWizardOutcome -ExitCode (-1) -Server 'APP01' -WarningAction SilentlyContinue
            $result.State | Should -Be 'Done'
            Should -Invoke -CommandName Get-SPSServersPatchStatus -ModuleName SPSUpdate.Common -Times 1 -Exactly
        }

        It 'does not query patch status for a successful exit code' {
            Mock -CommandName Get-SPSServersPatchStatus -ModuleName SPSUpdate.Common -MockWith { 'NoActionRequired' }
            Resolve-SPSWizardOutcome -ExitCode 0 -Server 'APP01' | Out-Null
            Should -Invoke -CommandName Get-SPSServersPatchStatus -ModuleName SPSUpdate.Common -Times 0 -Exactly
        }
    }
}
