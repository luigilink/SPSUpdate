# Tests for the example environment configuration and secret templates.
# Cross-platform: only validates psd1 parsing and the documented key contract.

$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$configDir  = Join-Path -Path $repoRoot -ChildPath 'src/Config'
$envExample = Join-Path -Path $configDir -ChildPath 'CONTOSO-PROD.example.psd1'
$secExample = Join-Path -Path $configDir -ChildPath 'secrets.example.psd1'

Describe 'Environment config example (CONTOSO-PROD.example.psd1)' {
    BeforeAll {
        $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
        $envExample = Join-Path -Path $repoRoot -ChildPath 'src/Config/CONTOSO-PROD.example.psd1'
        $cfg = Import-PowerShellDataFile -Path $envExample
    }

    It 'exists' {
        Test-Path -Path $envExample | Should -BeTrue
    }

    It 'parses as a PowerShell data file' {
        { Import-PowerShellDataFile -Path $envExample } | Should -Not -Throw
    }

    It 'defines every required identity key' {
        foreach ($key in @('ApplicationName', 'ConfigurationName', 'Domain', 'FarmName', 'CredentialKey')) {
            $cfg.ContainsKey($key) | Should -BeTrue
            [string]::IsNullOrWhiteSpace([string]$cfg[$key]) | Should -BeFalse
        }
    }

    It 'no longer uses the legacy StoredCredential key' {
        $cfg.ContainsKey('StoredCredential') | Should -BeFalse
    }

    It 'defines a Binaries block with SetupFullPath and SetupFileName' {
        $cfg.Binaries | Should -Not -BeNullOrEmpty
        $cfg.Binaries.ContainsKey('SetupFullPath') | Should -BeTrue
        $cfg.Binaries.SetupFileName | Should -Not -BeNullOrEmpty
    }

    It 'defines a SideBySideToken block' {
        $cfg.SideBySideToken | Should -Not -BeNullOrEmpty
        $cfg.SideBySideToken.ContainsKey('Enable') | Should -BeTrue
    }
}

Describe 'Secrets example (secrets.example.psd1)' {
    BeforeAll {
        $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
        $secExample = Join-Path -Path $repoRoot -ChildPath 'src/Config/secrets.example.psd1'
        $sec = Import-PowerShellDataFile -Path $secExample
    }

    It 'parses as a PowerShell data file' {
        { Import-PowerShellDataFile -Path $secExample } | Should -Not -Throw
    }

    It 'each entry has a Username and a PasswordSecure placeholder' {
        foreach ($key in $sec.Keys) {
            $sec[$key].ContainsKey('Username') | Should -BeTrue
            $sec[$key].ContainsKey('PasswordSecure') | Should -BeTrue
        }
    }

    It 'still carries the PASTE placeholder (no real secret committed)' {
        foreach ($key in $sec.Keys) {
            $sec[$key].PasswordSecure | Should -BeLike 'PASTE-*'
        }
    }
}
