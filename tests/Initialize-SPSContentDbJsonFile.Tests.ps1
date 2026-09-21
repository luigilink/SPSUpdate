# Tests for the ContentDatabase inventory generator (Initialize-SPSContentDbJsonFile).
# Get-SPContentDatabase is stubbed so these run cross-platform without SharePoint.
# The function is dot-sourced (rather than imported through the module) so the stub
# defined in the test scope is the one it resolves at call time.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:funcPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Initialize-SPSContentDbJsonFile.ps1'

    $script:tmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupd-initdb-" + [guid]::NewGuid())
    New-Item -Path $script:tmpDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
        Remove-Item -Path $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Initialize-SPSContentDbJsonFile - no content database (search farm)' {
    It 'writes a valid inventory with four empty sequences' {
        function Get-SPContentDatabase { $null }
        . $script:funcPath

        $path = Join-Path -Path $script:tmpDir -ChildPath 'app-PROD-SEARCH-ContentDBs.json'
        Initialize-SPSContentDbJsonFile -Path $path 6> $null

        Test-Path -Path $path | Should -BeTrue
        $cfg = Get-Content -Path $path -Raw | ConvertFrom-Json
        foreach ($n in 1..4) {
            @($cfg."SPContentDatabase$n" | Where-Object { $_ -and $_.Name }).Count | Should -Be 0
        }
    }

    It 'produces a property that reads back as an empty array (no phantom null entry)' {
        function Get-SPContentDatabase { $null }
        . $script:funcPath

        $path = Join-Path -Path $script:tmpDir -ChildPath 'app-PROD-SEARCH2-ContentDBs.json'
        Initialize-SPSContentDbJsonFile -Path $path 6> $null

        $cfg = Get-Content -Path $path -Raw | ConvertFrom-Json
        # @($null) would yield a one-element array; a real empty sequence yields zero.
        @($cfg.SPContentDatabase1).Count | Should -Be 0
    }
}

Describe 'Initialize-SPSContentDbJsonFile - with content databases' {
    It 'balances every database across the four sequences without loss' {
        function Get-SPContentDatabase {
            $mk = {
                param($n, $sz, $url)
                [pscustomobject]@{
                    Name             = $n
                    Server           = 'SQL1'
                    DiskSizeRequired = $sz
                    WebApplication   = [pscustomobject]@{ Url = $url }
                }
            }
            @(
                & $mk 'DB_Big' (3GB) 'https://portal'
                & $mk 'DB_Mid' (1GB) 'https://portal'
                & $mk 'DB_Small' (200MB) 'https://mysite'
            )
        }
        . $script:funcPath

        $path = Join-Path -Path $script:tmpDir -ChildPath 'app-PROD-CONTENT-ContentDBs.json'
        Initialize-SPSContentDbJsonFile -Path $path 6> $null

        $cfg = Get-Content -Path $path -Raw | ConvertFrom-Json
        $names = foreach ($n in 1..4) {
            $cfg."SPContentDatabase$n" | Where-Object { $_ -and $_.Name } | ForEach-Object { $_.Name }
        }
        @($names).Count | Should -Be 3
        $names | Should -Contain 'DB_Big'
        $names | Should -Contain 'DB_Mid'
        $names | Should -Contain 'DB_Small'
    }
}
