# Behavioural tests for the content-database wrappers Mount-SPSContentDatabase and
# Update-SPSContentDatabase. The SharePoint cmdlets they call do not exist off a farm,
# so they are declared as stubs (giving Pester a command to mock) and then mocked in the
# module scope. This hardens the exact plumbing that passes -Name/-WebApplication.

# The stubs mirror the real SharePoint cmdlets (including the unapproved "Upgrade" verb
# and a plain -Confirm parameter) and their parameters exist only so Pester can bind and
# mock them, so the related analyzer rules are suppressed for this test file.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Stubs mirror real SharePoint cmdlet names so Pester can mock them')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Stub parameters mirror the real cmdlets for mock binding only')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stub parameters exist only for mock parameter binding')]
param()

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Stubs so Pester can resolve and mock the SharePoint cmdlets used by the module.
    # They are defined at global scope so Mock -ModuleName can resolve them, and removed
    # again in AfterAll.
    function global:Get-SPContentDatabase { [CmdletBinding()] param($Identity) }
    function global:Get-SPWebApplication { [CmdletBinding()] param($Identity) }
    function global:Mount-SPContentDatabase { [CmdletBinding()] param($Name, $WebApplication, $DatabaseServer, $Confirm) }
    function global:Upgrade-SPContentDatabase { [CmdletBinding()] param([Parameter(Position = 0)] $Name, $Confirm) }
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
    foreach ($stub in 'Get-SPContentDatabase', 'Get-SPWebApplication', 'Mount-SPContentDatabase', 'Upgrade-SPContentDatabase') {
        if (Test-Path -Path "Function:\$stub") { Remove-Item -Path "Function:\$stub" -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Mount-SPSContentDatabase' {
    BeforeEach {
        Mock -CommandName Add-SPSUpdateEvent -ModuleName SPSUpdate.Common -MockWith {}
        Mock -CommandName Mount-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith {}
    }

    It 'is a no-op when the database is already mounted' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith { [pscustomobject]@{ Name = $Identity } }
        Mock -CommandName Get-SPWebApplication -ModuleName SPSUpdate.Common -MockWith {}

        Mount-SPSContentDatabase -Name 'DB1' -WebAppUrl 'https://portal' 6> $null

        Should -Invoke Mount-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }

    It 'throws when the target web application does not exist' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith { $null }
        Mock -CommandName Get-SPWebApplication -ModuleName SPSUpdate.Common -MockWith { $null }

        { Mount-SPSContentDatabase -Name 'DB1' -WebAppUrl 'https://portal' 6> $null } | Should -Throw
        Should -Invoke Mount-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }

    It 'does not mount under -WhatIf' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith { $null }
        Mock -CommandName Get-SPWebApplication -ModuleName SPSUpdate.Common -MockWith { [pscustomobject]@{ Url = $Identity } }

        Mount-SPSContentDatabase -Name 'DB1' -WebAppUrl 'https://portal' -WhatIf 6> $null

        Should -Invoke Mount-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }

    It 'mounts and forwards the optional database server' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith { $null }
        Mock -CommandName Get-SPWebApplication -ModuleName SPSUpdate.Common -MockWith { [pscustomobject]@{ Url = $Identity } }

        Mount-SPSContentDatabase -Name 'DB1' -WebAppUrl 'https://portal' -DatabaseServer 'SQL1' 6> $null

        Should -Invoke Mount-SPContentDatabase -ModuleName SPSUpdate.Common -Times 1 -Scope It -ParameterFilter {
            $Name -eq 'DB1' -and $WebApplication -eq 'https://portal' -and $DatabaseServer -eq 'SQL1'
        }
    }
}

Describe 'Update-SPSContentDatabase' {
    BeforeEach {
        Mock -CommandName Upgrade-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith {}
    }

    It 'upgrades when the database needs an upgrade' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith {
            [pscustomobject]@{ Name = $Identity; NeedsUpgrade = $true }
        }

        Update-SPSContentDatabase -Name 'DB1' 6> $null

        Should -Invoke Upgrade-SPContentDatabase -ModuleName SPSUpdate.Common -Times 1 -Scope It -ParameterFilter { $Name -eq 'DB1' }
    }

    It 'does not upgrade under -WhatIf' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith {
            [pscustomobject]@{ Name = $Identity; NeedsUpgrade = $true }
        }

        Update-SPSContentDatabase -Name 'DB1' -WhatIf 6> $null

        Should -Invoke Upgrade-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }

    It 'is a no-op when the database is already upgraded' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith {
            [pscustomobject]@{ Name = $Identity; NeedsUpgrade = $false }
        }

        Update-SPSContentDatabase -Name 'DB1' 6> $null

        Should -Invoke Upgrade-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }

    It 'is a no-op when the database does not exist' {
        Mock -CommandName Get-SPContentDatabase -ModuleName SPSUpdate.Common -MockWith { $null }

        Update-SPSContentDatabase -Name 'DB1' 6> $null

        Should -Invoke Upgrade-SPContentDatabase -ModuleName SPSUpdate.Common -Times 0 -Scope It
    }
}
