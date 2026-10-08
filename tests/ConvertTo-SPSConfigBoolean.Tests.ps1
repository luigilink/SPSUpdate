# Behavioural tests for ConvertTo-SPSConfigBoolean: the shared validator/normalizer
# that gives every Boolean configuration switch the same $true/$false/1/0 contract.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-SPSConfigBoolean' {
    Context 'Accepted values' {
        It 'returns $true for a $true Boolean' {
            ConvertTo-SPSConfigBoolean -Value $true -PropertyName 'Reboot.Enable' | Should -BeTrue
        }

        It 'returns $false for a $false Boolean' {
            ConvertTo-SPSConfigBoolean -Value $false -PropertyName 'Reboot.Enable' | Should -BeFalse
        }

        It 'normalizes the integer 1 to $true' {
            $result = ConvertTo-SPSConfigBoolean -Value 1 -PropertyName 'Reboot.Enable'
            $result | Should -BeOfType [System.Boolean]
            $result | Should -BeTrue
        }

        It 'normalizes the integer 0 to $false' {
            $result = ConvertTo-SPSConfigBoolean -Value 0 -PropertyName 'Reboot.Enable'
            $result | Should -BeOfType [System.Boolean]
            $result | Should -BeFalse
        }
    }

    Context 'Rejected values' {
        It 'throws for an out-of-range integer' {
            { ConvertTo-SPSConfigBoolean -Value 2 -PropertyName 'Reboot.Enable' } |
                Should -Throw -ExpectedMessage "*'Reboot.Enable'*"
        }

        It 'rejects the string "1" (no string coercion)' {
            { ConvertTo-SPSConfigBoolean -Value '1' -PropertyName 'Reboot.Force' } |
                Should -Throw -ExpectedMessage "*'Reboot.Force'*"
        }

        It 'rejects the string "0" (no string coercion)' {
            { ConvertTo-SPSConfigBoolean -Value '0' -PropertyName 'Reboot.Force' } | Should -Throw
        }

        It 'rejects an arbitrary truthy string such as "false"' {
            { ConvertTo-SPSConfigBoolean -Value 'false' -PropertyName 'Remoting.AllowFallback' } |
                Should -Throw -ExpectedMessage "*'Remoting.AllowFallback'*"
        }

        It 'rejects "yes"' {
            { ConvertTo-SPSConfigBoolean -Value 'yes' -PropertyName 'Execution.InteractiveSequences' } | Should -Throw
        }

        It 'rejects $null' {
            { ConvertTo-SPSConfigBoolean -Value $null -PropertyName 'Reboot.Enable' } | Should -Throw
        }

        It 'names the offending property in the error message' {
            { ConvertTo-SPSConfigBoolean -Value 7 -PropertyName 'Binaries.ProductUpdate' } |
                Should -Throw -ExpectedMessage "*'Binaries.ProductUpdate'*"
        }
    }
}
