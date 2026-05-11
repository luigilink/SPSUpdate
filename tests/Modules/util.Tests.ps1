# Resolve repo root - works on both local and CI/CD
$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path -Path $repoRoot -ChildPath 'scripts/Modules/util.psm1'

Import-Module -Name $modulePath -Force

Describe 'util.psm1 Module' {
    It 'module loads successfully' {
        Get-Module -Name util | Should -Not -BeNullOrEmpty
    }

    It 'exports Get-SPSInstalledProductVersion' {
        Get-Command -Name Get-SPSInstalledProductVersion -Module util | Should -Not -BeNullOrEmpty
    }

    It 'exports Add-SPSUpdateEvent' {
        Get-Command -Name Add-SPSUpdateEvent -Module util | Should -Not -BeNullOrEmpty
    }

    It 'exports Invoke-SPSCommand' {
        Get-Command -Name Invoke-SPSCommand -Module util | Should -Not -BeNullOrEmpty
    }

    It 'exports Test-SPSPendingReboot' {
        Get-Command -Name Test-SPSPendingReboot -Module util | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-SPSInstalledProductVersion' {
    It 'returns FileVersionInfo when a SharePoint binary path is found' -Skip:(-not $IsWindows) {
        Mock -ModuleName util -CommandName Get-Item -MockWith {
            [pscustomobject]@{
                FullName  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                Directory = '16\ISAPI'
            }
        }

        $result = Get-SPSInstalledProductVersion

        $result | Should -BeOfType ([System.Diagnostics.FileVersionInfo])
    }

    It 'throws a descriptive error when no SharePoint binary path is found' -Skip:(-not $IsWindows) {
        Mock -ModuleName util -CommandName Get-Item -MockWith { $null }

        { Get-SPSInstalledProductVersion -ErrorAction Stop } | Should -Throw '*SharePoint path*does not exist*'
    }
}

Describe 'Add-SPSUpdateEvent' {
    It 'has Message parameter as mandatory' {
        $cmd = Get-Command -Name Add-SPSUpdateEvent -Module util
        $param = $cmd.Parameters['Message']
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -Be $true
    }

    It 'has Source parameter as mandatory' {
        $cmd = Get-Command -Name Add-SPSUpdateEvent -Module util
        $param = $cmd.Parameters['Source']
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -Be $true
    }

    It 'has EntryType with ValidateSet' {
        $cmd = Get-Command -Name Add-SPSUpdateEvent -Module util
        $cmd.Parameters['EntryType'].Attributes.Where{ $_.TypeId.Name -eq 'ValidateSetAttribute' } | Should -Not -BeNullOrEmpty
    }

    It 'function is callable with parameters' -Skip:(-not $IsWindows) {
        Mock -ModuleName util -CommandName Write-EventLog -MockWith {}
        { Add-SPSUpdateEvent -Message 'Test' -Source 'TestSource' -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Invoke-SPSCommand' {
    It 'has Credential parameter' {
        $cmd = Get-Command -Name Invoke-SPSCommand -Module util
        $cmd.Parameters.Keys | Should -Contain 'Credential'
    }

    It 'has Server parameter' {
        $cmd = Get-Command -Name Invoke-SPSCommand -Module util
        $cmd.Parameters.Keys | Should -Contain 'Server'
    }

    It 'has ScriptBlock parameter' {
        $cmd = Get-Command -Name Invoke-SPSCommand -Module util
        $cmd.Parameters.Keys | Should -Contain 'ScriptBlock'
    }
}

Describe 'Start-SPSScheduledTask' {
    It 'has TaskPath parameter' {
        $cmd = Get-Command -Name Start-SPSScheduledTask -Module util
        $cmd.Parameters.Keys | Should -Contain 'TaskPath'
    }

    It 'normalizes TaskPath and starts task when task exists' {
        Mock -ModuleName util -CommandName Get-ScheduledTask -MockWith {
            [pscustomobject]@{ TaskName = 'SPSUpdate-Sequence1'; State = 'Ready' }
        }
        Mock -ModuleName util -CommandName Start-ScheduledTask -MockWith { }

        $result = Start-SPSScheduledTask -Name 'SPSUpdate-Sequence1' -TaskPath 'SharePoint' -Confirm:$false

        $result.Name | Should -Be 'SPSUpdate-Sequence1'
        $result.TaskPath | Should -Be '\SharePoint\'
        $result.State | Should -Be 'Ready'

        Assert-MockCalled -ModuleName util -CommandName Get-ScheduledTask -Times 2 -Exactly -ParameterFilter {
            $TaskName -eq 'SPSUpdate-Sequence1' -and $TaskPath -eq '\SharePoint\'
        }
        Assert-MockCalled -ModuleName util -CommandName Start-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'SPSUpdate-Sequence1' -and $TaskPath -eq '\SharePoint\'
        }
    }

    It 'throws a clear message when task does not exist in given TaskPath' {
        Mock -ModuleName util -CommandName Get-ScheduledTask -MockWith { $null }
        Mock -ModuleName util -CommandName Start-ScheduledTask -MockWith { }

        { Start-SPSScheduledTask -Name 'MissingTask' -TaskPath 'SharePoint' -Confirm:$false } | Should -Throw 'Scheduled Task MissingTask does not exist in SharePoint Task Path'

        Assert-MockCalled -ModuleName util -CommandName Start-ScheduledTask -Times 0
    }
}

Describe 'Test-SPSPendingReboot' {
    It 'returns IsPending false when no reboot markers exist' {
        Mock -ModuleName util -CommandName Test-Path -MockWith { $false }
        Mock -ModuleName util -CommandName Get-ItemProperty -MockWith { $null }

        $result = Test-SPSPendingReboot

        $result.IsPending | Should -Be $false
        $result.Reasons.Count | Should -Be 0
    }

    It 'returns IsPending true when reboot-required registry key exists' {
        Mock -ModuleName util -CommandName Test-Path -MockWith {
            param($Path)
            if ($Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                return $true
            }
            return $false
        }
        Mock -ModuleName util -CommandName Get-ItemProperty -MockWith { $null }

        $result = Test-SPSPendingReboot

        $result.IsPending | Should -Be $true
        $result.Reasons | Should -Contain 'WindowsUpdateRebootRequired'
    }

    It 'does not flag WindowsUpdateServicesPending when Pending key has no child entries' {
        Mock -ModuleName util -CommandName Test-Path -MockWith {
            param($Path)
            if ($Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending') {
                return $true
            }
            return $false
        }
        Mock -ModuleName util -CommandName Get-ChildItem -MockWith { @() }
        Mock -ModuleName util -CommandName Get-ItemProperty -MockWith { $null }

        $result = Test-SPSPendingReboot

        $result.IsPending | Should -Be $false
        $result.Reasons | Should -Not -Contain 'WindowsUpdateServicesPending'
    }

    It 'flags WindowsUpdateServicesPending when Pending key has child entries' {
        Mock -ModuleName util -CommandName Test-Path -MockWith {
            param($Path)
            if ($Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending') {
                return $true
            }
            return $false
        }
        Mock -ModuleName util -CommandName Get-ChildItem -MockWith {
            @([pscustomobject]@{ Name = 'Service1' })
        }
        Mock -ModuleName util -CommandName Get-ItemProperty -MockWith { $null }

        $result = Test-SPSPendingReboot

        $result.IsPending | Should -Be $true
        $result.Reasons | Should -Contain 'WindowsUpdateServicesPending'
    }
}
