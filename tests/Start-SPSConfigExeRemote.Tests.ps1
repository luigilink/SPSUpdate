# Behavioural tests for Start-SPSConfigExeRemote exit-code handling.
# Cross-platform by design: Invoke-SPSCommand (the remoting call) is mocked, so no
# SharePoint or WinRM is required. Runs on pwsh 7 / macOS and on windows-latest.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Start-SPSConfigExeRemote builds a path from CommonProgramFiles; ensure it resolves on
    # non-Windows hosts so the function reaches the mocked Invoke-SPSCommand call.
    if ([string]::IsNullOrWhiteSpace($env:CommonProgramFiles)) {
        $env:CommonProgramFiles = [System.IO.Path]::GetTempPath()
    }

    $script:cred = [System.Management.Automation.PSCredential]::new(
        'CONTOSO\svc', (New-Object System.Security.SecureString))
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Start-SPSConfigExeRemote' {
    It 'throws when the remote run returns no exit code' {
        Mock -CommandName Invoke-SPSCommand -ModuleName SPSUpdate.Common -MockWith { $null }
        { Start-SPSConfigExeRemote -Server 'APP01' -InstallAccount $script:cred } |
            Should -Throw -ExpectedMessage '*did not return an exit code*'
    }

    It 'throws when the remote run returns a non-integer result' {
        Mock -CommandName Invoke-SPSCommand -ModuleName SPSUpdate.Common -MockWith { 'some stdout but no code' }
        { Start-SPSConfigExeRemote -Server 'APP01' -InstallAccount $script:cred } |
            Should -Throw -ExpectedMessage '*did not return an exit code*'
    }

    It 'returns the exit code when the remote run completes successfully' {
        Mock -CommandName Invoke-SPSCommand -ModuleName SPSUpdate.Common -MockWith { 0 }
        Start-SPSConfigExeRemote -Server 'APP01' -InstallAccount $script:cred -WarningAction SilentlyContinue |
            Should -Be 0
    }

    It 'returns a non-zero exit code (does not throw) and warns' {
        Mock -CommandName Invoke-SPSCommand -ModuleName SPSUpdate.Common -MockWith { 17022 }
        $warnings = $null
        $code = Start-SPSConfigExeRemote -Server 'APP01' -InstallAccount $script:cred -WarningVariable warnings -WarningAction SilentlyContinue
        $code | Should -Be 17022
        $warnings | Should -Not -BeNullOrEmpty
    }
}
