# Tests for Start-SPSProductUpdate: services are always restored, also when the installer or the shutdown fails,
# and an interrupted previous update is repaired first.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Private/Get-SPSServiceStatePath.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Start-SPSProductUpdate.ps1')

    function Add-SPSUpdateEvent { [CmdletBinding()] param([string] $Message, [string] $Source, [string] $EntryType) }
    function Get-SPSLocalVersionInfo { [CmdletBinding()] param([switch] $IsWssPackage) }
    function Stop-SPSUpdateServices { [CmdletBinding()] param([string] $ShutdownProfile, [bool] $GracefulStopDistributedCache, [string] $StateFolder, [string] $StatePath) }
    function Restore-SPSUpdateServices { [CmdletBinding()] param([string] $Path, [string] $StateFolder) }

    $script:Setup = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('uber-subscription-test-' + [guid]::NewGuid() + '.exe')
    Set-Content -Path $script:Setup -Value 'x'
}

AfterAll {
    Remove-Item -Path $script:Setup -Force -ErrorAction SilentlyContinue
}

Describe 'Start-SPSProductUpdate service handling' {
    BeforeEach {
        $script:LastStatePath = $null
        Mock Get-SPSLocalVersionInfo { [version]'16.0.1.1' }
        Mock Get-ItemProperty { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ FileVersion = '16.0.9.9' } } }
        Mock Get-Item { $null }
        Mock Add-SPSUpdateEvent { }
        # The real function writes the state file before changing anything: the mock does the same.
        Mock Stop-SPSUpdateServices { $script:LastStatePath = $StatePath; New-Item -Path (Split-Path -Parent $StatePath) -ItemType Directory -Force | Out-Null; Set-Content -Path $StatePath -Value '{}'; [pscustomobject]@{ Path = $StatePath; ShutdownProfile = $ShutdownProfile; Services = @() } }
        Mock Restore-SPSUpdateServices { if ($Path) { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }; $true }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'passes the profile, the graceful option and the state path to the service shutdown, then restores the services' {
        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -ServiceShutdownProfile Extended -GracefulStopDistributedCache $true -Confirm:$false

        $rc | Should -Be 0
        Should -Invoke Stop-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $ShutdownProfile -eq 'Extended' -and $GracefulStopDistributedCache -eq $true -and -not [string]::IsNullOrEmpty($StatePath) }
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq $script:LastStatePath }
    }

    It 'uses the Basic profile by default' {
        $null = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false
        Should -Invoke Stop-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $ShutdownProfile -eq 'Basic' -and $GracefulStopDistributedCache -eq $false }
    }

    It 'restores the services even when the installer fails' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }

        { Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false } | Should -Throw '*install failed*'

        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq $script:LastStatePath }
    }

    It 'restores the services when the shutdown itself fails after it changed something' {
        Mock Stop-SPSUpdateServices { $script:LastStatePath = $StatePath; New-Item -Path (Split-Path -Parent $StatePath) -ItemType Directory -Force | Out-Null; Set-Content -Path $StatePath -Value '{}'; throw 'iisreset could not be launched' }

        { Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false } | Should -Throw '*iisreset could not be launched*'

        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq $script:LastStatePath }
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'does not try to restore anything when the shutdown failed before any state file was written' {
        Mock Stop-SPSUpdateServices { throw 'the services of an interrupted ProductUpdate could not be restored' }

        { Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false } | Should -Throw '*could not be restored*'

        Should -Invoke Restore-SPSUpdateServices -Times 0 -Exactly -ParameterFilter { $Path }
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'still returns 17022 (reboot required) and restores the services' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 17022 } }

        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false

        $rc | Should -Be 17022
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $Path -eq $script:LastStatePath }
    }

    It 'repairs an interrupted previous update before anything else' {
        $null = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $StateFolder }
    }

    It 'repairs an interrupted previous update even when the package is already installed' {
        Mock Get-SPSLocalVersionInfo { [version]'16.0.99.0' }

        $rc = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $true -Confirm:$false

        $rc | Should -BeNullOrEmpty
        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $StateFolder }
        Should -Invoke Stop-SPSUpdateServices -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'repairs an interrupted previous update even when ShutdownServices is false, without stopping any service' {
        $null = Start-SPSProductUpdate -SetupFile $script:Setup -ShutdownServices $false -Confirm:$false

        Should -Invoke Restore-SPSUpdateServices -Times 1 -Exactly -ParameterFilter { $StateFolder }
        Should -Invoke Stop-SPSUpdateServices -Times 0 -Exactly
        Should -Invoke Restore-SPSUpdateServices -Times 0 -Exactly -ParameterFilter { $Path }
    }
}
