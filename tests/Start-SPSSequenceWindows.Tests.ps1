# Behavioural tests for Start-SPSSequenceWindows.
# Cross-platform by design: Start-Process is mocked, so no real windows are launched.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Start-SPSSequenceWindows' {
    It 'starts one window per sequence and returns a process per window' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = Get-Random } }
            Mock Start-Sleep { }

            $procs = Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 4 -StartDelaySeconds 0
            $procs.Count | Should -Be 4
            Should -Invoke Start-Process -Times 4 -Exactly
        }
    }

    It 'uses Windows PowerShell (powershell.exe) by default, not pwsh' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }
            Mock Start-Sleep { }

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 1 -StartDelaySeconds 0 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'powershell.exe' }
        }
    }

    It 'passes -Sequence N and the config file to each window' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }
            Mock Start-Sleep { }

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 2 -StartDelaySeconds 0 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '-Sequence 1' -and $ArgumentList -match 'cfg\.psd1' }
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '-Sequence 2' }
        }
    }

    It 'staggers starts between windows but not after the last one' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }
            Mock Start-Sleep { }

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 4 -StartDelaySeconds 30 | Out-Null
            # 4 windows -> 3 inter-start delays.
            Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -eq 30 }
        }
    }

    It 'honours -PassThru so the caller can wait on the processes' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1 } }
            Mock Start-Sleep { }

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 1 -StartDelaySeconds 0 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $PassThru -eq $true }
        }
    }
}
