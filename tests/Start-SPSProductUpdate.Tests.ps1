# Tests for Start-SPSProductUpdate: services are always restored, also when the installer fails.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Start-SPSProductUpdate.ps1')

    function Add-SPSUpdateEvent { [CmdletBinding()] param([string] $Message, [string] $Source, [string] $EntryType) }
    function Get-SPSLocalVersionInfo { [CmdletBinding()] param([switch] $IsWssPackage) }
    function Stop-SPSUpdateServices { [CmdletBinding()] param([string] $ShutdownProfile, [bool] $GracefulStopDistributedCache, [string] $StateFolder) }
    function Restore-SPSUpdateServices { [CmdletBinding()] param([string] $Path) }

    $script:Setup = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('uber-subscription-test-' + [guid]::NewGuid() + '.exe')
    Set-Content -Path $script:Setup -Value 'x'
}

AfterAll {
    Remove-Item -Path $script:Setup -Force -ErrorAction SilentlyContinue
}

Describe 'Start-SPSProductUpdate service handling' {
    BeforeEach {
        Mock Get-SPSLocalVersionInfo { [version]'16.0.1.1' }
        Mock Get-ItemProperty { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ FileVersion = '16.0.9.9' } } }
        Mock Get-Item { $null }
        Mock Add-SPSUpdateEvent { }
        Mock Stop-SPSUpdateServices { [pscustomobject]@{ Path = 'state.json'; ShutdownProfile = $ShutdownProfile; Services = @() } }
        Mock Restore-SPSUpdateServices { $true }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'passes the profile and the graceful option to the service shutdown, then restores the services' {
        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -ServiceShutdownProfile Extended -GracefulStopDistributedCache $true -Confirm:$false

        $rc | Should -Be 0
        Should -Invoke Stop-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $ShutdownProfile -eq 'Extended' -and $GracefulStopDistributedCache -eq $true }
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq 'state.json' }
    }

    It 'uses the Basic profile by default' {
        $null = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false
        Should -Invoke Stop-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $ShutdownProfile -eq 'Basic' -and $GracefulStopDistributedCache -eq $false }
    }

    It 'restores the services even when the installer fails' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }

        { Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false } | Should -Throw '*install failed*'

        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq 'state.json' }
    }

    It 'still returns 17022 (reboot required) and restores the services' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 17022 } }

        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false

        $rc | Should -Be 17022
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly
    }

    It 'does not touch any service when ShutdownServices is false' {
        $null = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $false -Confirm:$false

        Should -Invoke Stop-SPSUpdateServices -Times 0 -Exactly
        Should -Invoke Restore-SPSUpdateServices -Times 0 -Exactly
    }

    It 'does nothing when the update is already installed' {
        Mock Get-SPSLocalVersionInfo { [version]'16.0.99.0' }

        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false

        $rc | Should -BeNullOrEmpty
        Should -Invoke Stop-SPSUpdateServices -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
