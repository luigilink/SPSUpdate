$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'scripts/Modules/util.psm1') -Force
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'scripts/Modules/sps.util.psm1') -Force

if (-not (Get-Command -Name Get-Service -ErrorAction SilentlyContinue)) {
    function global:Get-Service { param([string[]]$Name) }
}
if (-not (Get-Command -Name Set-Service -ErrorAction SilentlyContinue)) {
    function global:Set-Service { param([string]$Name, [string]$StartupType) }
}
if (-not (Get-Command -Name Stop-Service -ErrorAction SilentlyContinue)) {
    function global:Stop-Service { param([string]$Name, [switch]$Force) }
}
if (-not (Get-Command -Name Start-Service -ErrorAction SilentlyContinue)) {
    function global:Start-Service { param([string]$Name) }
}

Describe 'Get-SPSLocalVersionInfo' {
    It 'returns product DisplayVersion when patch metadata is missing' {
        Mock -ModuleName sps.util -CommandName Get-ChildItem -MockWith {
            @([pscustomobject]@{ PsPath = 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Installer\\UserData\\S-1-5-18\\Products\\00000000F01FEC' })
        }

        Mock -ModuleName sps.util -CommandName Get-ItemProperty -ParameterFilter { $Path -like '*InstallProperties' } -MockWith {
            [pscustomobject]@{
                DisplayName    = 'Microsoft SharePoint Server 2019 Core'
                DisplayVersion = '16.0.10337.12109'
            }
        }

        Mock -ModuleName sps.util -CommandName Get-ItemProperty -ParameterFilter { $Path -like '*\\Patches' } -MockWith {
            [pscustomobject]@{ AllPatches = $null }
        }

        Mock -ModuleName sps.util -CommandName Get-ItemProperty -MockWith {
            [pscustomobject]@{}
        }

        $result = Get-SPSLocalVersionInfo -ProductVersion '2019'

        $result | Should -BeOfType ([version])
        $result.ToString() | Should -Be '16.0.10337.12109'
    }
}

Describe 'Start-SPSProductUpdate' {
    BeforeEach {
        $securePassword = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
        $script:testCredential = New-Object System.Management.Automation.PSCredential ('CONTOSO\\spinstall', $securePassword)

        Mock -ModuleName sps.util -CommandName Test-Path -MockWith { $true }
        Mock -ModuleName sps.util -CommandName Get-ItemProperty -ParameterFilter { $Path -eq 'C:\\setup.exe' } -MockWith {
            [pscustomobject]@{ VersionInfo = [pscustomobject]@{ FileVersion = '16.0.20000.10000' } }
        }
        Mock -ModuleName sps.util -CommandName Get-SPSLocalVersionInfo -MockWith { [version]'16.0.10000.10000' }
        Mock -ModuleName sps.util -CommandName Get-SPSInstalledProductVersion -MockWith { [pscustomobject]@{ ProductMajorPart = 16 } }
        Mock -ModuleName sps.util -CommandName Add-SPSUpdateEvent
        Mock -ModuleName sps.util -CommandName Start-Process -MockWith { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'throws and logs when setup file is blocked' -Skip:(-not $IsWindows) {
        Mock -ModuleName sps.util -CommandName Get-Item -MockWith {
            [pscustomobject]@{ Stream = 'Zone.Identifier' }
        }

        { Start-SPSProductUpdate -InstallAccount $script:testCredential -SetupFile 'C:\\setup.exe' -ShutdownServices $false } |
            Should -Throw '*Setup file is blocked*'

        Assert-MockCalled -ModuleName sps.util -CommandName Add-SPSUpdateEvent -Times 1 -Exactly
    }

    It 'reports the actual setupInstall exit code when installation fails' {
        Mock -ModuleName sps.util -CommandName Get-Item -ParameterFilter { $Path -eq 'C:\\setup.exe' -and $Stream -eq 'Zone.Identifier' } -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Start-Process -ParameterFilter { $FilePath -eq 'C:\\setup.exe' } -MockWith {
            [pscustomobject]@{ ExitCode = 1234 }
        }

        {
            Start-SPSProductUpdate -InstallAccount $script:testCredential -SetupFile 'C:\\setup.exe' -ShutdownServices $false
        } | Should -Throw '*exit code was 1234*'
    }

    It 'restores original startup type for services that were previously stopped' {
        Mock -ModuleName sps.util -CommandName Get-Item -ParameterFilter { $Path -eq 'C:\\setup.exe' -and $Stream -eq 'Zone.Identifier' } -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Get-SPSInstalledProductVersion -MockWith { [pscustomobject]@{ ProductMajorPart = 15 } }

        Mock -ModuleName sps.util -CommandName Get-Service -MockWith {
            @([pscustomobject]@{ Name = 'SPSearchHostController'; StartType = 'Manual'; Status = 'Stopped' })
        }
        Mock -ModuleName sps.util -CommandName Stop-Service
        Mock -ModuleName sps.util -CommandName Start-Service
        Mock -ModuleName sps.util -CommandName Set-Service
        Mock -ModuleName sps.util -CommandName Set-Content
        Mock -ModuleName sps.util -CommandName Get-Content -MockWith {
            '[{"Name":"SPSearchHostController","StartType":"Manual","Status":"Stopped"}]'
        }

        Mock -ModuleName sps.util -CommandName Start-Process -ParameterFilter { $FilePath -eq 'C:\\setup.exe' } -MockWith {
            [pscustomobject]@{ ExitCode = 0 }
        }

        Start-SPSProductUpdate -InstallAccount $script:testCredential -SetupFile 'C:\\setup.exe' -ShutdownServices $true

        Assert-MockCalled -ModuleName sps.util -CommandName Get-Service -Times 1 -ParameterFilter { $Name -contains 'OSearch15' }
        Assert-MockCalled -ModuleName sps.util -CommandName Set-Service -Times 1 -ParameterFilter {
            $Name -eq 'SPSearchHostController' -and $StartupType -eq 'Manual'
        }
    }
}
