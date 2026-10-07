# Metadata/binding tests for Add-SPSScheduledTask parameter sets.
# Cross-platform by design: these assert the command's parameter-set contract only; they do not
# register a scheduled task (the COM registration is Windows-only).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:cmd = Get-Command Add-SPSScheduledTask
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Add-SPSScheduledTask parameter sets' {
    It 'places RunAsSystem and ExecuteAsCredential in distinct parameter sets' {
        $runAsSystemSets = $script:cmd.Parameters['RunAsSystem'].ParameterSets.Keys
        $credentialSets = $script:cmd.Parameters['ExecuteAsCredential'].ParameterSets.Keys
        # No shared set between the two, so they cannot be supplied together.
        (@($runAsSystemSets) | Where-Object { $credentialSets -contains $_ }) | Should -BeNullOrEmpty
    }

    It 'makes ExecuteAsCredential mandatory in the Credential (default) set and absent from the System set' {
        $credParam = $script:cmd.Parameters['ExecuteAsCredential']
        $credParam.ParameterSets.ContainsKey('Credential') | Should -BeTrue
        $credParam.ParameterSets['Credential'].IsMandatory | Should -BeTrue
        $credParam.ParameterSets.ContainsKey('System') | Should -BeFalse
    }

    It 'exposes RunAsSystem only in the System set and as a switch (not mandatory)' {
        $sysParam = $script:cmd.Parameters['RunAsSystem']
        $sysParam.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
        $sysParam.ParameterSets.ContainsKey('System') | Should -BeTrue
        $sysParam.ParameterSets['System'].IsMandatory | Should -BeFalse
        $sysParam.ParameterSets.ContainsKey('Credential') | Should -BeFalse
    }

    It 'rejects supplying RunAsSystem and ExecuteAsCredential together' {
        $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (New-Object System.Security.SecureString))
        {
            Add-SPSScheduledTask -Name 'T' -ActionArguments '-x' -TaskPath 'SharePoint' `
                -RunAsSystem -ExecuteAsCredential $cred -ErrorAction Stop
        } | Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
    }
}
