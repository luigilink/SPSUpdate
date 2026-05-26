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
if (-not (Get-Command -Name Get-SPContentDatabase -ErrorAction SilentlyContinue)) {
    function global:Get-SPContentDatabase { param([string]$Identity) }
}
if (-not (Get-Command -Name Get-SPWebApplication -ErrorAction SilentlyContinue)) {
    function global:Get-SPWebApplication { param([string]$Identity) }
}
if (-not (Get-Command -Name Mount-SPContentDatabase -ErrorAction SilentlyContinue)) {
    function global:Mount-SPContentDatabase {
        param(
            [string]$Name,
            [string]$WebApplication,
            [string]$DatabaseServer,
            [switch]$Confirm
        )
    }
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
    It 'does not expose InstallAccount parameter anymore' {
        $cmd = Get-Command -Name Start-SPSProductUpdate -ErrorAction Stop
        $cmd.Parameters.Keys | Should -Not -Contain 'InstallAccount'
    }

    BeforeEach {
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

        { Start-SPSProductUpdate -SetupFile 'C:\\setup.exe' -ShutdownServices $false } |
            Should -Throw '*Setup file is blocked*'

        Assert-MockCalled -ModuleName sps.util -CommandName Add-SPSUpdateEvent -Times 1 -Exactly
    }

    It 'reports the actual setupInstall exit code when installation fails' {
        Mock -ModuleName sps.util -CommandName Get-Item -ParameterFilter { $Path -eq 'C:\\setup.exe' -and $Stream -eq 'Zone.Identifier' } -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Start-Process -ParameterFilter { $FilePath -eq 'C:\\setup.exe' } -MockWith {
            [pscustomobject]@{ ExitCode = 1234 }
        }

        {
            Start-SPSProductUpdate -SetupFile 'C:\\setup.exe' -ShutdownServices $false
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

        Start-SPSProductUpdate -SetupFile 'C:\\setup.exe' -ShutdownServices $true

        Assert-MockCalled -ModuleName sps.util -CommandName Get-Service -Times 1 -ParameterFilter { $Name -contains 'OSearch15' }
        Assert-MockCalled -ModuleName sps.util -CommandName Set-Service -Times 1 -ParameterFilter {
            $Name -eq 'SPSearchHostController' -and $StartupType -eq 'Manual'
        }
    }
}

Describe 'Mount-SPSContentDatabase' {
    It 'is exported from sps.util module' {
        # Inspect the module export table directly. Avoid `Get-Command -Module sps.util`
        # because on Windows PowerShell 5.1 the -Module filter throws a terminating
        # CommandNotFoundException for module names containing a dot, even when the
        # function is loaded and callable (which the other tests in this Describe verify).
        $module = Get-Module -Name 'sps.util'
        $module | Should -Not -BeNullOrEmpty
        $module.ExportedCommands.ContainsKey('Mount-SPSContentDatabase') | Should -BeTrue
    }

    It 'exposes Name, WebAppUrl and DatabaseServer parameters' {
        $cmd = Get-Command -Name Mount-SPSContentDatabase -ErrorAction Stop
        $cmd.Parameters.Keys | Should -Contain 'Name'
        $cmd.Parameters.Keys | Should -Contain 'WebAppUrl'
        $cmd.Parameters.Keys | Should -Contain 'DatabaseServer'
    }

    It 'skips mounting when the content database is already attached to the farm' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith {
            [pscustomobject]@{ Name = 'WSS_Content_Test' }
        }
        Mock -ModuleName sps.util -CommandName Get-SPWebApplication -MockWith {
            [pscustomobject]@{ Url = 'https://intranet.contoso.com' }
        }
        Mock -ModuleName sps.util -CommandName Mount-SPContentDatabase
        Mock -ModuleName sps.util -CommandName Add-SPSUpdateEvent

        Mount-SPSContentDatabase -Name 'WSS_Content_Test' -WebAppUrl 'https://intranet.contoso.com'

        Assert-MockCalled -ModuleName sps.util -CommandName Mount-SPContentDatabase -Times 0 -Exactly
    }

    It 'mounts the database when it is not already attached' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Get-SPWebApplication -MockWith {
            [pscustomobject]@{ Url = 'https://intranet.contoso.com' }
        }
        Mock -ModuleName sps.util -CommandName Mount-SPContentDatabase
        Mock -ModuleName sps.util -CommandName Add-SPSUpdateEvent

        Mount-SPSContentDatabase -Name 'WSS_Content_New' -WebAppUrl 'https://intranet.contoso.com' -DatabaseServer 'SQL01'

        Assert-MockCalled -ModuleName sps.util -CommandName Mount-SPContentDatabase -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'WSS_Content_New' -and $WebApplication -eq 'https://intranet.contoso.com' -and $DatabaseServer -eq 'SQL01'
        }
    }

    It 'throws when the target web application does not exist' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Get-SPWebApplication -MockWith { $null }
        Mock -ModuleName sps.util -CommandName Mount-SPContentDatabase
        Mock -ModuleName sps.util -CommandName Add-SPSUpdateEvent

        { Mount-SPSContentDatabase -Name 'WSS_Content_Orphan' -WebAppUrl 'https://missing.contoso.com' } |
            Should -Throw '*SPWebApplication*not found*'

        Assert-MockCalled -ModuleName sps.util -CommandName Mount-SPContentDatabase -Times 0 -Exactly
        Assert-MockCalled -ModuleName sps.util -CommandName Add-SPSUpdateEvent -Times 1 -Exactly
    }
}
