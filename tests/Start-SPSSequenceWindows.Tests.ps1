# Behavioural tests for Start-SPSSequenceWindows (orchestrator).
# Cross-platform by design: Start-Process / Start-Sleep are mocked, so no real windows launch.

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
    It 'starts one window per sequence (powershell.exe) and returns a process each' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = Get-Random; HasExited = $true; ExitCode = 0 } }
            Mock Start-Sleep { }

            $r = Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 4 -StartDelaySeconds 0
            $r.Processes.Count | Should -Be 4
            $r.FailedSequences.Count | Should -Be 0
            Should -Invoke Start-Process -Times 4 -Exactly
            Should -Invoke Start-Process -Times 4 -Exactly -ParameterFilter { $FilePath -eq 'powershell.exe' -and $PassThru -eq $true }
        }
    }

    It 'passes -Sequence N and the config file to each window' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1; HasExited = $true; ExitCode = 0 } }
            Mock Start-Sleep { }

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 2 -StartDelaySeconds 0 | Out-Null
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '-Sequence 1' -and $ArgumentList -match 'cfg\.psd1' }
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '-Sequence 2' }
        }
    }

    It 'staggers starts between windows but not after the last one' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1; HasExited = $true; ExitCode = 0 } }
            Mock Start-Sleep { }

            # 4 windows, delay 30, poll 10 -> 3 staggers * 3 chunks of 10 = 9 sleeps.
            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 4 -StartDelaySeconds 30 -PollSeconds 10 | Out-Null
            Should -Invoke Start-Sleep -Times 9 -Exactly -ParameterFilter { $Seconds -eq 10 }
        }
    }

    It 'invokes the dashboard callback during the run' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { [PSCustomObject]@{ Id = 1; HasExited = $true; ExitCode = 0 } }
            Mock Start-Sleep { }
            $script:refreshCount = 0

            Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 2 -StartDelaySeconds 0 `
                -DashboardCallback { $script:refreshCount++ } | Out-Null
            $script:refreshCount | Should -BeGreaterThan 0
        }
    }

    It 'reports sequences whose window returned a non-zero exit code' {
        InModuleScope SPSUpdate.Common {
            $script:n = 0
            Mock Start-Process {
                $script:n++
                # Second window fails (exit 1), others succeed.
                $code = if ($script:n -eq 2) { 1 } else { 0 }
                [PSCustomObject]@{ Id = $script:n; HasExited = $true; ExitCode = $code }
            }
            Mock Start-Sleep { }

            $r = Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 3 -StartDelaySeconds 0
            $r.FailedSequences | Should -Be @(2)
        }
    }

    It 'propagates a terminating launch failure' {
        InModuleScope SPSUpdate.Common {
            Mock Start-Process { throw 'cannot start process' }
            Mock Start-Sleep { }

            { Start-SPSSequenceWindows -ScriptPath 'C:\x\SPSUpdate.ps1' -ConfigFile 'cfg.psd1' -Count 2 -StartDelaySeconds 0 } |
                Should -Throw -ExpectedMessage '*cannot start process*'
        }
    }
}
