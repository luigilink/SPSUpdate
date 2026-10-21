# Behavioural tests for Set-SPSSideBySideToken retry semantics on transient
# SPWebService update conflicts.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    function New-TestWebApp {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Boolean]
            $EnableSideBySide,

            [Parameter(Mandatory = $true)]
            [System.String]
            $SideBySideToken,

            [Parameter(Mandatory = $true)]
            [System.Int32]
            $FailCount,

            [Parameter(Mandatory = $true)]
            [System.String]
            $ErrorMessage
        )

        $webService = [pscustomobject]@{
            EnableSideBySide   = $EnableSideBySide
            SideBySideToken    = $SideBySideToken
            AttemptCount       = 0
            FailCount          = $FailCount
            UpdateErrorMessage = $ErrorMessage
        }

        Add-Member -InputObject $webService -MemberType ScriptMethod -Name Update -Value {
            $this.AttemptCount++
            if ($this.AttemptCount -le $this.FailCount) {
                throw [System.Exception]::new($this.UpdateErrorMessage)
            }
        } -Force

        return [pscustomobject]@{
            Name       = 'http://portal'
            WebService = $webService
        }
    }

    function global:Get-SPWebApplication {
        [CmdletBinding()]
        param(
            [Parameter()]
            [System.String]
            $Identity
        )

        $script:GetSpWebAppCallCount++
        if ($PSBoundParameters.ContainsKey('Identity')) {
            $script:GetSpWebAppIdentityCallCount++
            if ($null -ne $script:IdentityResolver) {
                return & $script:IdentityResolver $Identity
            }
            if ($null -ne $script:WebAppsByIdentity -and $script:WebAppsByIdentity.ContainsKey($Identity)) {
                return $script:WebAppsByIdentity[$Identity]
            }
            return $null
        }

        return $script:WebApps
    }

    function global:Copy-SPSideBySideFiles {
        $script:CopyCalls++
    }
}

AfterAll {
    Remove-Item -Path Function:\global:Get-SPWebApplication -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\global:Copy-SPSideBySideFiles -ErrorAction SilentlyContinue
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Set-SPSSideBySideToken - bounded retry on update conflict' {
    BeforeEach {
        $script:WebApps = @()
        $script:WebAppsByIdentity = @{}
        $script:IdentityResolver = $null
        $script:StaleWebApp = $null
        $script:FreshWebApp = $null
        $script:SwappedToFresh = $false
        $script:CopyCalls = 0
        $script:GetSpWebAppCallCount = 0
        $script:GetSpWebAppIdentityCallCount = 0
    }

    It 'retries update-conflict exceptions and then succeeds' {
        $webApp = New-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 2 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'
        $script:WebApps = @($webApp)
        $script:WebAppsByIdentity = @{ 'http://portal' = $webApp }

        Mock -CommandName Start-Sleep -ModuleName SPSUpdate.Common -MockWith {}

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Not -Throw

        $webApp.WebService.AttemptCount | Should -Be 3
        Should -Invoke -CommandName Start-Sleep -ModuleName SPSUpdate.Common -Times 2 -Exactly -ParameterFilter { $Seconds -eq 15 }
        $script:CopyCalls | Should -Be 1
        $webApp.WebService.SideBySideToken | Should -Be '16.0.20326.20190'
    }

    It 'fails after 6 attempts when conflict persists' {
        $webApp = New-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 99 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'
        $script:WebApps = @($webApp)
        $script:WebAppsByIdentity = @{ 'http://portal' = $webApp }

        Mock -CommandName Start-Sleep -ModuleName SPSUpdate.Common -MockWith {}

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Throw -ExpectedMessage '*update conflict has occurred*'

        $webApp.WebService.AttemptCount | Should -Be 6
        Should -Invoke -CommandName Start-Sleep -ModuleName SPSUpdate.Common -Times 5 -Exactly -ParameterFilter { $Seconds -eq 15 }
        $script:CopyCalls | Should -Be 0
    }

    It 'does not retry non-conflict exceptions' {
        $webApp = New-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 1 -ErrorMessage 'Access denied.'
        $script:WebApps = @($webApp)
        $script:WebAppsByIdentity = @{ 'http://portal' = $webApp }

        Mock -CommandName Start-Sleep -ModuleName SPSUpdate.Common -MockWith {}

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Throw -ExpectedMessage '*Access denied*'

        $webApp.WebService.AttemptCount | Should -Be 1
        Should -Invoke -CommandName Start-Sleep -ModuleName SPSUpdate.Common -Times 0 -Exactly
    }

    It 'refreshes a stale SPWebService instance between retries' {
        $stale = New-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 99 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'
        $fresh = New-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 0 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'
        $script:WebApps = @($stale)
        $script:WebAppsByIdentity = @{ 'http://portal' = $stale }
        $script:SwappedToFresh = $false

        Mock -CommandName Start-Sleep -ModuleName SPSUpdate.Common -MockWith {
            if (-not $script:SwappedToFresh) {
                $script:WebAppsByIdentity['http://portal'] = $fresh
                $script:SwappedToFresh = $true
            }
        }

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Not -Throw

        $stale.WebService.AttemptCount | Should -Be 1
        $fresh.WebService.AttemptCount | Should -Be 1
        $script:GetSpWebAppIdentityCallCount | Should -Be 2
        $script:SwappedToFresh | Should -BeTrue
        Should -Invoke -CommandName Start-Sleep -ModuleName SPSUpdate.Common -Times 1 -Exactly -ParameterFilter { $Seconds -eq 15 }
        $script:CopyCalls | Should -Be 1
    }
}
