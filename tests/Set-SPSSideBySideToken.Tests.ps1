# Behavioural tests for Set-SPSSideBySideToken retry semantics on transient
# SPWebService update conflicts.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -name $modulePath -Force

    function new-TestWebApp {
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
            EnableSideBySide     = $EnableSideBySide
            SideBySideToken      = $SideBySideToken
            AttemptCount         = 0
            FailCount            = $FailCount
            UpdateErrorMessage   = $ErrorMessage
        }
        Add-Member -InputObject $webService -MemberType ScriptMethod -name Update -Value {
            $this.AttemptCount++
            if ($this.AttemptCount -le $this.FailCount) {
                throw [System.Exception]::new($this.UpdateErrorMessage)
            }
        } -Force

        return [pscustomobject]@{
            name       = 'http://portal'
            WebService = $webService
        }
    }
}

AfterAll {
    Remove-Module -name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Set-SPSSideBySideToken - bounded retry on update conflict' {
    AfterEach {
        Remove-Item -Path Function:\global:Get-SPWebApplication -ErrorAction SilentlyContinue
        Remove-Item -Path Function:\global:Copy-SPSideBySideFiles -ErrorAction SilentlyContinue
    }

    It 'retries update-conflict exceptions and then succeeds' {
        $webApp = new-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 2 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'

        $script:TestWebApps = @($webApp)
        $script:CopyCalls = 0
        function global:Get-SPWebApplication { return $script:TestWebApps }
        function global:Copy-SPSideBySideFiles { $script:CopyCalls++ }
        Mock -Commandname Start-Sleep -Modulename SPSUpdate.Common -MockWith {}

        $warnings = $null
        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false -WarningVariable warnings -WarningAction Continue } |
            Should -not -Throw

        $webApp.WebService.AttemptCount | Should -Be 3
        Should -Invoke -Commandname Start-Sleep -Modulename SPSUpdate.Common -Times 2 -Exactly -ParameterFilter { $Seconds -eq 15 }
        $script:CopyCalls | Should -Be 1
        $webApp.WebService.SideBySideToken | Should -Be '16.0.20326.20190'
    }

    It 'fails after 6 attempts when conflict persists' {
        $webApp = new-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 99 -ErrorMessage 'An update conflict has occurred, and you must re-try this action.'

        $script:TestWebApps = @($webApp)
        $script:CopyCalls = 0
        function global:Get-SPWebApplication { return $script:TestWebApps }
        function global:Copy-SPSideBySideFiles { $script:CopyCalls++ }
        Mock -Commandname Start-Sleep -Modulename SPSUpdate.Common -MockWith {}

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Throw -ExpectedMessage '*update conflict has occurred*'

        $webApp.WebService.AttemptCount | Should -Be 6
        Should -Invoke -Commandname Start-Sleep -Modulename SPSUpdate.Common -Times 5 -Exactly -ParameterFilter { $Seconds -eq 15 }
        $script:CopyCalls | Should -Be 0
    }

    It 'does not retry non-conflict exceptions' {
        $webApp = new-TestWebApp -EnableSideBySide $true -SideBySideToken '16.0.10000.10000' -FailCount 1 -ErrorMessage 'Access denied.'

        $script:TestWebApps = @($webApp)
        $script:CopyCalls = 0
        function global:Get-SPWebApplication { return $script:TestWebApps }
        function global:Copy-SPSideBySideFiles { $script:CopyCalls++ }
        Mock -Commandname Start-Sleep -Modulename SPSUpdate.Common -MockWith {}

        { Set-SPSSideBySideToken -BuildVersion '16.0.20326.20190' -EnableSideBySide $true -Confirm:$false } |
            Should -Throw -ExpectedMessage '*Access denied*'

        $webApp.WebService.AttemptCount | Should -Be 1
        Should -Invoke -Commandname Start-Sleep -Modulename SPSUpdate.Common -Times 0 -Exactly
    }
}
