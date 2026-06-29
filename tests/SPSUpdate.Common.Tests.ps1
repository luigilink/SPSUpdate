# Structural tests for the SPSUpdate.Common module and SPSUpdate.ps1 entry script.
# Cross-platform by design (no SharePoint / no Windows-only dependency) so they run
# on pwsh 7 / macOS locally and on windows-latest in CI.

$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$moduleDir  = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
$modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'

$publicFiles  = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Public')  -Filter *.ps1)
$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Private') -Filter *.ps1)
$functionFiles = @($publicFiles + $privateFiles)
$psFiles = @(
    $functionFiles
    Get-Item -Path $modulePath
    Get-Item -Path (Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psm1')
    Get-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src/SPSUpdate.ps1')
)

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir  = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'SPSUpdate.Common module' {
    It 'imports without error' {
        Get-Module -Name SPSUpdate.Common | Should -Not -BeNullOrEmpty
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $modulePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'manifest version is 4.0.0 or higher' {
        (Test-ModuleManifest -Path $modulePath).Version | Should -BeGreaterOrEqual ([version]'4.0.0')
    }

    It 'exports exactly the expected public functions' {
        $expected = @(
            'Add-SPSScheduledTask'
            'Add-SPSUpdateEvent'
            'Copy-SPSSideBySideFilesRemote'
            'Get-SPSInstalledProductVersion'
            'Get-SPSSecret'
            'Get-SPSServersPatchStatus'
            'Initialize-SPSContentDbJsonFile'
            'Mount-SPSContentDatabase'
            'Remove-SPSScheduledTask'
            'Set-SPSSecret'
            'Set-SPSSideBySideToken'
            'Start-SPSConfigExe'
            'Start-SPSConfigExeRemote'
            'Start-SPSProductUpdate'
            'Start-SPSScheduledTask'
            'Test-SPSPendingReboot'
            'Update-SPSContentDatabase'
        )
        $actual = (Get-Command -Module SPSUpdate.Common -CommandType Function).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not export the private helpers' {
        foreach ($name in @('Invoke-SPSCommand', 'Clear-ComObject', 'Get-SPSLocalVersionInfo', 'Get-SPSConfigRoot')) {
            Get-Command -Name $name -Module SPSUpdate.Common -CommandType Function -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }

    It 'exports the Copy-SPSSideBySideFilesAllServers alias' {
        $alias = Get-Command -Name 'Copy-SPSSideBySideFilesAllServers' -Module SPSUpdate.Common -CommandType Alias -ErrorAction SilentlyContinue
        $alias | Should -Not -BeNullOrEmpty
        $alias.ResolvedCommand.Name | Should -Be 'Copy-SPSSideBySideFilesRemote'
    }

    It 'manifest FunctionsToExport matches the Public folder exactly' {
        $declared = (Import-PowerShellDataFile -Path $modulePath).FunctionsToExport | Sort-Object
        $files = (Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Public') -Filter *.ps1).BaseName |
            Sort-Object
        $declared | Should -Be $files
    }

    It 'every exported function uses an approved verb' {
        $approved = (Get-Verb).Verb
        foreach ($command in (Get-Command -Module SPSUpdate.Common -CommandType Function)) {
            $approved | Should -Contain $command.Verb
        }
    }
}

Describe 'Module file conventions' {
    It '<Name> defines exactly one function named after the file' -ForEach $functionFiles {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs)
        $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $fns.Count | Should -Be 1
        $fns[0].Name | Should -Be $_.BaseName
    }

    It '<Name> parses without errors' -ForEach $functionFiles {
        $tokens = $null; $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs) | Out-Null
        $errs | Should -BeNullOrEmpty
    }

    It '<Name> is stored as UTF-8 with BOM' -ForEach $psFiles {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }
}

Describe 'Public function contracts' {
    It '<_> supports ShouldProcess (WhatIf/Confirm)' -ForEach @('Remove-SPSScheduledTask', 'Start-SPSScheduledTask', 'Mount-SPSContentDatabase', 'Update-SPSContentDatabase', 'Set-SPSSideBySideToken', 'Start-SPSProductUpdate', 'Set-SPSSecret') {
        (Get-Command -Name $_ -Module SPSUpdate.Common).Parameters.Keys |
            Should -Contain 'WhatIf'
    }

    It '<_> requires a mandatory -Name' -ForEach @('Add-SPSScheduledTask', 'Remove-SPSScheduledTask', 'Start-SPSScheduledTask') {
        $param = (Get-Command -Name $_ -Module SPSUpdate.Common).Parameters['Name']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Add-SPSScheduledTask exposes an optional -Description parameter' {
        $param = (Get-Command -Name Add-SPSScheduledTask -Module SPSUpdate.Common).Parameters['Description']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeFalse
    }

    It 'Add-SPSScheduledTask creates or updates the task (mode 6)' {
        $src = (Get-Command -Name Add-SPSScheduledTask -Module SPSUpdate.Common).Definition
        $src | Should -Match 'RegisterTaskDefinition\([^)]*6,'
    }

    It 'Add-SPSUpdateEvent requires a mandatory -Message and -Source' {
        $cmd = Get-Command -Name Add-SPSUpdateEvent -Module SPSUpdate.Common
        foreach ($p in @('Message', 'Source')) {
            $cmd.Parameters[$p].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        }
    }

    It 'Add-SPSUpdateEvent restricts -EntryType with a ValidateSet' {
        $cmd = Get-Command -Name Add-SPSUpdateEvent -Module SPSUpdate.Common
        $validate = $cmd.Parameters['EntryType'].Attributes.Where{ $_.TypeId.Name -eq 'ValidateSetAttribute' }
        $validate | Should -Not -BeNullOrEmpty
        $validate[0].ValidValues | Should -Contain 'Information'
        $validate[0].ValidValues | Should -Contain 'Warning'
        $validate[0].ValidValues | Should -Contain 'Error'
    }

    It 'Add-SPSUpdateEvent writes to the SPSUpdate event log and self-heals a misrouted source' {
        $src = (Get-Command -Name Add-SPSUpdateEvent -Module SPSUpdate.Common).Definition
        $src | Should -Match "LogName\s*=\s*'SPSUpdate'"
        $src | Should -Match 'DeleteEventSource'
    }

    It 'Get-SPSSecret requires a mandatory -CredentialKey' {
        $param = (Get-Command -Name Get-SPSSecret -Module SPSUpdate.Common).Parameters['CredentialKey']
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Set-SPSSecret exposes a -Remove switch and -CredentialKey' {
        $cmd = Get-Command -Name Set-SPSSecret -Module SPSUpdate.Common
        $cmd.Parameters.Keys | Should -Contain 'Remove'
        $cmd.Parameters['CredentialKey'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Mount-SPSContentDatabase requires -Name and -WebAppUrl' {
        $cmd = Get-Command -Name Mount-SPSContentDatabase -Module SPSUpdate.Common
        foreach ($p in @('Name', 'WebAppUrl')) {
            $cmd.Parameters[$p].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        }
    }

    It 'Get-SPSInstalledProductVersion returns null off a SharePoint server' -Skip:($IsWindows -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')) {
        Get-SPSInstalledProductVersion | Should -BeNullOrEmpty
    }
}

Describe 'Secret store round-trip (DPAPI on Windows only)' {
    It 'Set-SPSSecret then Get-SPSSecret returns the same username' -Skip:(-not $IsWindows) {
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupdate-secret-" + [guid]::NewGuid())
        try {
            $sec = ConvertTo-SecureString -String 'P@ssw0rd!test' -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential('CONTOSO\svc_test', $sec)
            Set-SPSSecret -CredentialKey 'UNIT-TEST' -Credential $cred -ConfigPath $tmp -Confirm:$false
            $back = Get-SPSSecret -CredentialKey 'UNIT-TEST' -ConfigPath $tmp
            $back.UserName | Should -Be 'CONTOSO\svc_test'
        }
        finally {
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-SPSSecret returns null when secrets.psd1 is missing' {
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupdate-missing-" + [guid]::NewGuid())
        Get-SPSSecret -CredentialKey 'NOPE' -ConfigPath $tmp | Should -BeNullOrEmpty
    }
}
