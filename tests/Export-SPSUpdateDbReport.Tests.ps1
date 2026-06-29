# Tests for the ContentDatabase inventory HTML report (Export-SPSUpdateDbReport).
# Cross-platform: pure string/HTML generation, no SharePoint dependency.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:tmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupd-report-" + [guid]::NewGuid())
    New-Item -Path $script:tmpDir -ItemType Directory -Force | Out-Null

    # Inventory WITH size (v4.1.0+ shape)
    $script:invWithSize = [pscustomobject]@{
        SPContentDatabase1 = @([pscustomobject]@{ Name = 'DB_A'; Server = 'SQL1'; WebAppUrl = 'https://intranet'; SizeInBytes = 3221225472; SizeInMB = 3072 })
        SPContentDatabase2 = @(
            [pscustomobject]@{ Name = 'DB_B'; Server = 'SQL1'; WebAppUrl = 'https://mysite'; SizeInBytes = 1073741824; SizeInMB = 1024 }
            [pscustomobject]@{ Name = 'DB_C <x> & "y"'; Server = 'SQL2'; WebAppUrl = 'https://extranet'; SizeInBytes = 2147483648; SizeInMB = 2048 }
        )
        SPContentDatabase3 = @([pscustomobject]@{ Name = 'DB_D'; Server = 'SQL2'; WebAppUrl = 'https://intranet'; SizeInBytes = 2684354560; SizeInMB = 2560 })
        SPContentDatabase4 = @([pscustomobject]@{ Name = 'DB_E'; Server = 'SQL1'; WebAppUrl = 'https://intranet'; SizeInBytes = 2952790016; SizeInMB = 2816 })
    }

    # Legacy inventory WITHOUT size (pre-4.1.0 shape)
    $script:invNoSize = [pscustomobject]@{
        SPContentDatabase1 = @([pscustomobject]@{ Name = 'OLD_A'; Server = 'SQL1'; WebAppUrl = 'https://intranet' })
        SPContentDatabase2 = @([pscustomobject]@{ Name = 'OLD_B'; Server = 'SQL1'; WebAppUrl = 'https://mysite' })
        SPContentDatabase3 = @()
        SPContentDatabase4 = @()
    }
}

AfterAll {
    if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
        Remove-Item -Path $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Export-SPSUpdateDbReport (with size)' {
    BeforeAll {
        $script:outWith = Join-Path -Path $script:tmpDir -ChildPath 'with-size.html'
        $script:returned = Export-SPSUpdateDbReport -InputObject $script:invWithSize -OutputFile $script:outWith `
            -EnvName 'PROD' -AppCode 'contoso' -FarmName 'CONTENT' -Version '4.1.0'
        $script:htmlWith = Get-Content -Path $script:outWith -Raw
    }

    It 'returns the output path and writes the file' {
        $script:returned | Should -Be $script:outWith
        Test-Path $script:outWith | Should -BeTrue
    }

    It 'produces a self-contained HTML document (no external resources)' {
        $script:htmlWith | Should -Match '<!DOCTYPE html>'
        $script:htmlWith | Should -Match '<style>'
        $script:htmlWith | Should -Match '<script>'
        $script:htmlWith | Should -Not -Match 'src="http'
        $script:htmlWith | Should -Not -Match 'href="http'
    }

    It 'shows the total size and renders the distribution bars' {
        # 3072+1024+2048+2560+2816 = 11520 MB
        $script:htmlWith | Should -Match '11[\s,\u00a0]?520'
        $script:htmlWith | Should -Match 'dist-fill'
        $script:htmlWith | Should -Match 'Size \(MB\)'
    }

    It 'neutralizes markup from database names inside the JSON payload' {
        # The raw, unescaped name must never appear; it is encoded as \u003c etc.
        $script:htmlWith | Should -Not -Match '"Name":"DB_C <'
        $script:htmlWith | Should -Match 'DB_C \\u003cx\\u003e'
    }

    It 'embeds every database row' {
        foreach ($n in @('DB_A', 'DB_B', 'DB_D', 'DB_E')) {
            $script:htmlWith | Should -Match $n
        }
    }
}

Describe 'Export-SPSUpdateDbReport (legacy inventory without size)' {
    BeforeAll {
        $script:outNo = Join-Path -Path $script:tmpDir -ChildPath 'no-size.html'
        Export-SPSUpdateDbReport -InputObject $script:invNoSize -OutputFile $script:outNo -Version '4.1.0' | Out-Null
        $script:htmlNo = Get-Content -Path $script:outNo -Raw
    }

    It 'still renders and flags missing size information' {
        Test-Path $script:outNo | Should -BeTrue
        $script:htmlNo | Should -Match 'No size information'
        $script:htmlNo | Should -Match 'n/a'
    }

    It 'distributes by count when size is unavailable' {
        $script:htmlNo | Should -Match 'by count'
    }
}

Describe 'Export-SPSUpdateDbReport (from a JSON file)' {
    It 'reads the inventory from disk and writes the report' {
        $jsonPath = Join-Path -Path $script:tmpDir -ChildPath 'inv.json'
        $script:invWithSize | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
        $outPath = Join-Path -Path $script:tmpDir -ChildPath 'from-file.html'
        $result = Export-SPSUpdateDbReport -InputFile $jsonPath -OutputFile $outPath
        $result | Should -Be $outPath
        (Get-Content -Path $outPath -Raw) | Should -Match '<!DOCTYPE html>'
    }

    It 'throws when the input file is missing' {
        { Export-SPSUpdateDbReport -InputFile (Join-Path $script:tmpDir 'nope.json') -OutputFile (Join-Path $script:tmpDir 'x.html') } |
            Should -Throw '*input file not found*'
    }
}
