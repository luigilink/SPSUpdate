# Behavioural tests for Start-SPSSequenceWindow.
# Cross-platform by design: Start-Process is mocked, so no real window is launched.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Start-SPSSequenceWindow' {
    It 'starts a single window and returns its process' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 123 } }

            $proc = Start-SPSSequenceWindow -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Sequence 1
            $proc.Id | Should -Be 123
            Should -Invoke Start-Process -Times 1 -Exactly
        }
    }

    It 'uses Windows PowerShell (powershell.exe) by default, not pwsh' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }

            Start-SPSSequenceWindow -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Sequence 1 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'powershell.exe' }
        }
    }

    It 'passes -Sequence N and the config file to the window' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }

            Start-SPSSequenceWindow -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Sequence 3 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '-Sequence 3' -and $ArgumentList -match 'cfg\.psd1' }
        }
    }

    It 'honours -PassThru so the caller can wait on the process' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }

            Start-SPSSequenceWindow -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Sequence 1 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $PassThru -eq $true }
        }
    }

    It 'returns only the process object (no stream pollution)' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 7 } }

            $result = @(Start-SPSSequenceWindow -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Sequence 1)
            $result.Count | Should -Be 1
        }
    }
}
