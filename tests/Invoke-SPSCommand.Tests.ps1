# Behavioural tests for Invoke-SPSCommand authentication chain (CredSSP -> Negotiate).
# Cross-platform by design: the private helper is exercised via InModuleScope and the real
# remoting cmdlets are mocked, so no remoting occurs. Runs on pwsh 7 / macOS and CI.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-SPSCommand authentication chain' {
    It 'uses CredSSP only and does not fall back when AllowFallback is off' {
        InModuleScope SPSUpdate.Common {
            Mock Get-SPSRemoteSessionOption { [PSCustomObject]@{} }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession { }
            Mock New-PSSession { New-MockObject -Type ([System.Management.Automation.Runspaces.PSSession]) }

            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
            $result = Invoke-SPSCommand -Credential $cred -Server 'APP01' -ScriptBlock { 'x' }

            $result | Should -Be 'remote-output'
            Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'CredSSP' }
            Should -Invoke New-PSSession -Times 0 -Exactly -ParameterFilter { $Authentication -eq 'Negotiate' }
        }
    }

    It 'throws the original CredSSP error when CredSSP fails and fallback is off' {
        InModuleScope SPSUpdate.Common {
            Mock Get-SPSRemoteSessionOption { [PSCustomObject]@{} }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession { }
            Mock New-PSSession { throw 'CredSSP not configured' }

            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
            { Invoke-SPSCommand -Credential $cred -Server 'APP01' -ScriptBlock { 'x' } -WarningAction SilentlyContinue } |
                Should -Throw -ExpectedMessage '*Failed to open a CredSSP PSSession*'
        }
    }

    It 'falls back to Negotiate when CredSSP fails and AllowFallback is on' {
        InModuleScope SPSUpdate.Common {
            Mock Get-SPSRemoteSessionOption { [PSCustomObject]@{} }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession { }
            Mock New-PSSession {
                if ($Authentication -eq 'CredSSP') { throw 'CredSSP not configured' }
                New-MockObject -Type ([System.Management.Automation.Runspaces.PSSession])
            }

            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
            $warnings = $null
            $result = Invoke-SPSCommand -Credential $cred -Server 'APP01' -ScriptBlock { 'x' } `
                -AllowFallback -WarningVariable warnings -WarningAction SilentlyContinue

            $result | Should -Be 'remote-output'
            $warningText = (@($warnings) | ForEach-Object { $_.ToString() }) -join "`n"
            $warningText | Should -Match 'Negotiate'
            $warningText | Should -Match 'Kerberos delegation'
            Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'CredSSP' }
            Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'Negotiate' }
        }
    }

    It 'throws an aggregated error that keeps every authentication method error' {
        InModuleScope SPSUpdate.Common {
            Mock Get-SPSRemoteSessionOption { [PSCustomObject]@{} }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession { }
            Mock New-PSSession {
                if ($Authentication -eq 'CredSSP') { throw 'credssp-down' }
                throw 'negotiate-down'
            }

            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
            try {
                Invoke-SPSCommand -Credential $cred -Server 'APP01' -ScriptBlock { 'x' } `
                    -AllowFallback -WarningAction SilentlyContinue
                throw 'should have thrown'
            }
            catch {
                $_.Exception.Message | Should -Match 'using any of: CredSSP, Negotiate'
                $_.Exception.Message | Should -Match 'credssp-down'
                $_.Exception.Message | Should -Match 'negotiate-down'
            }
        }
    }

    It 'does not run the remote command when no session can be opened' {
        InModuleScope SPSUpdate.Common {
            Mock Get-SPSRemoteSessionOption { [PSCustomObject]@{} }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession { }
            Mock New-PSSession { throw 'unreachable' }

            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
            { Invoke-SPSCommand -Credential $cred -Server 'APP01' -ScriptBlock { 'x' } -WarningAction SilentlyContinue } |
                Should -Throw
            Should -Invoke Invoke-Command -Times 0 -Exactly
        }
    }
}
