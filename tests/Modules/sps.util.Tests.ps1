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
        $cmd = Get-Command -Name Mount-SPSContentDatabase -ErrorAction Stop
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.CommandType | Should -Be 'Function'
        $cmd.ModuleName | Should -Not -BeNullOrEmpty
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

Describe 'Initialize-SPSContentDbJsonFile' {
    BeforeEach {
        $script:tempJsonPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath ("sps-contentdb-{0}.json" -f [guid]::NewGuid())
    }

    AfterEach {
        if ($script:tempJsonPath) {
            # Remove the canonical file AND any timestamped snapshots produced alongside it.
            $dir  = Split-Path -Path $script:tempJsonPath -Parent
            $base = [System.IO.Path]::GetFileNameWithoutExtension($script:tempJsonPath)
            Get-ChildItem -Path $dir -Filter "$base*.json" -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    function script:New-FakeSPDb {
        param(
            [string]$Name,
            [long]$Size,
            [string]$Server = 'SQL01',
            [string]$Url = 'https://intranet.contoso.com'
        )
        [pscustomobject]@{
            Name             = $Name
            Server           = $Server
            DiskSizeRequired = $Size
            WebApplication   = [pscustomobject]@{ Url = $Url }
        }
    }

    It 'writes no file when Get-SPContentDatabase returns $null' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith { $null }

        Initialize-SPSContentDbJsonFile -Path $script:tempJsonPath

        Test-Path -Path $script:tempJsonPath | Should -Be $false

        # And no timestamped snapshot either
        $dir  = Split-Path -Path $script:tempJsonPath -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($script:tempJsonPath)
        @(Get-ChildItem -Path $dir -Filter "$base*.json" -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'distributes 3 databases across 3 distinct sequences (regression: old code put them all in sequence 4)' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith {
            @(
                (New-FakeSPDb -Name 'WSS_Content_A' -Size 30MB)
                (New-FakeSPDb -Name 'WSS_Content_B' -Size 20MB)
                (New-FakeSPDb -Name 'WSS_Content_C' -Size 10MB)
            )
        }

        Initialize-SPSContentDbJsonFile -Path $script:tempJsonPath

        $json = Get-Content -Path $script:tempJsonPath -Raw | ConvertFrom-Json

        # Use .Where({$_}) to safely count: ConvertFrom-Json yields $null for "[]",
        # and @($null).Count is 1 (not 0) so a naive @(...).Count would mislead.
        @($json.SPContentDatabase1).Where({ $_ }).Count | Should -Be 1
        @($json.SPContentDatabase2).Where({ $_ }).Count | Should -Be 1
        @($json.SPContentDatabase3).Where({ $_ }).Count | Should -Be 1
        @($json.SPContentDatabase4).Where({ $_ }).Count | Should -Be 0

        # LPT: largest first → Seq1 gets the 30MB DB
        $json.SPContentDatabase1.Name | Should -Be 'WSS_Content_A'
        $json.SPContentDatabase2.Name | Should -Be 'WSS_Content_B'
        $json.SPContentDatabase3.Name | Should -Be 'WSS_Content_C'
    }

    It 'balances databases by total DiskSizeRequired rather than by count' {
        # Worst case for the old "floor(count/4)" splitter: one large DB plus many small ones.
        # Old code would put DBs 1..(N/4) into Seq1 (incl. the giant one) and dump the rest into Seq4.
        # LPT should land the giant DB alone in one sequence and spread the small ones across the others.
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith {
            @(
                (New-FakeSPDb -Name 'WSS_Content_BIG' -Size 100MB)
                (New-FakeSPDb -Name 'WSS_Content_S1'  -Size 10MB)
                (New-FakeSPDb -Name 'WSS_Content_S2'  -Size 10MB)
                (New-FakeSPDb -Name 'WSS_Content_S3'  -Size 10MB)
                (New-FakeSPDb -Name 'WSS_Content_S4'  -Size 10MB)
                (New-FakeSPDb -Name 'WSS_Content_S5'  -Size 10MB)
                (New-FakeSPDb -Name 'WSS_Content_S6'  -Size 10MB)
            )
        }

        Initialize-SPSContentDbJsonFile -Path $script:tempJsonPath

        $json = Get-Content -Path $script:tempJsonPath -Raw | ConvertFrom-Json

        $sequences = @(
            $json.SPContentDatabase1
            $json.SPContentDatabase2
            $json.SPContentDatabase3
            $json.SPContentDatabase4
        )

        # All 7 databases must be present exactly once across the 4 sequences.
        $allNames = $sequences | ForEach-Object { @($_).Where({ $_ }).Name }
        @($allNames).Count | Should -Be 7
        @($allNames | Sort-Object -Unique).Count | Should -Be 7

        # Sequence containing the big DB must hold ONLY the big DB
        # (otherwise the splitter never beat the makespan of the largest single job).
        $bigSequences = @(
            foreach ($seq in $sequences) {
                $names = @($seq).Where({ $_ }).Name
                if ($names -contains 'WSS_Content_BIG') { , $names }
            }
        )
        $bigSequences.Count | Should -Be 1
        $bigSequences[0].Count | Should -Be 1
    }

    It 'produces the SPContentDatabase1..4 JSON contract consumed by SPSUpdate.ps1' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith {
            @(
                (New-FakeSPDb -Name 'WSS_Content_X' -Size 5MB)
                (New-FakeSPDb -Name 'WSS_Content_Y' -Size 5MB)
                (New-FakeSPDb -Name 'WSS_Content_Z' -Size 5MB)
                (New-FakeSPDb -Name 'WSS_Content_W' -Size 5MB)
            )
        }

        Initialize-SPSContentDbJsonFile -Path $script:tempJsonPath

        $json = Get-Content -Path $script:tempJsonPath -Raw | ConvertFrom-Json
        $json.PSObject.Properties.Name | Should -Contain 'SPContentDatabase1'
        $json.PSObject.Properties.Name | Should -Contain 'SPContentDatabase2'
        $json.PSObject.Properties.Name | Should -Contain 'SPContentDatabase3'
        $json.PSObject.Properties.Name | Should -Contain 'SPContentDatabase4'

        # Each entry preserves Name / Server / WebAppUrl
        $first = $json.SPContentDatabase1
        $first.Name      | Should -Not -BeNullOrEmpty
        $first.Server    | Should -Be 'SQL01'
        $first.WebAppUrl | Should -Be 'https://intranet.contoso.com'
    }

    It 'writes a timestamped snapshot alongside the canonical file with matching content' {
        Mock -ModuleName sps.util -CommandName Get-SPContentDatabase -MockWith {
            @( (New-FakeSPDb -Name 'WSS_Content_A' -Size 10MB) )
        }

        Initialize-SPSContentDbJsonFile -Path $script:tempJsonPath

        # Canonical file is written (existing contract)
        Test-Path -Path $script:tempJsonPath | Should -Be $true

        # A snapshot named <basename>_<yyyy-MM-dd_HH-mm-ss>.json lives next to it
        $dir  = Split-Path -Path $script:tempJsonPath -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($script:tempJsonPath)
        $ext  = [System.IO.Path]::GetExtension($script:tempJsonPath)
        $snapshotPattern = "^$([regex]::Escape($base))_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$([regex]::Escape($ext))$"
        $snapshots = @(
            Get-ChildItem -Path $dir -Filter "$base*$ext" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $snapshotPattern }
        )
        $snapshots.Count | Should -Be 1

        # Snapshot content is identical to the canonical file
        (Get-Content -Path $script:tempJsonPath -Raw) |
            Should -Be (Get-Content -Path $snapshots[0].FullName -Raw)
    }
}
