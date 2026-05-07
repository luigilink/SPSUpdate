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
}

Describe 'Get-SPSInstalledProductVersion' {
    It 'function is callable' -Skip:(-not $IsWindows) {
        { Get-SPSInstalledProductVersion -ErrorAction SilentlyContinue } | Should -Not -Throw
    }

    It 'returns FileVersionInfo or null' -Skip:(-not $IsWindows) {
        $result = Get-SPSInstalledProductVersion -ErrorAction SilentlyContinue
        ($result -eq $null) -or ($result -is [System.Diagnostics.FileVersionInfo]) | Should -Be $true
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
