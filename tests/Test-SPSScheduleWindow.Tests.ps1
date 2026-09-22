# Tests for the schedule-window helper Test-SPSScheduleWindow.
# Pure date/time logic with an injectable -Now, fully cross-platform.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force

    # 2026-09-26 is a Saturday; 2026-09-28 is a Monday.
    $script:sat0300 = [datetime]'2026-09-26T03:00:00'
    $script:sat0500 = [datetime]'2026-09-26T05:00:00'
    $script:mon0300 = [datetime]'2026-09-28T03:00:00'
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Test-SPSScheduleWindow' {
    It 'returns true when neither days nor time are restricted' {
        Test-SPSScheduleWindow -Now $script:sat0300 | Should -BeTrue
    }

    It 'allows the current day when it is in the day list' {
        Test-SPSScheduleWindow -Days @('sat', 'sun') -Now $script:sat0300 | Should -BeTrue
    }

    It 'blocks the current day when it is not in the day list' {
        Test-SPSScheduleWindow -Days @('sat', 'sun') -Now $script:mon0300 | Should -BeFalse
    }

    It 'is case-insensitive and tolerates full day names' {
        Test-SPSScheduleWindow -Days @('Saturday', 'SUN') -Now $script:sat0300 | Should -BeTrue
    }

    It 'allows a time inside the window' {
        Test-SPSScheduleWindow -Time '2:00 AM to 4:00 AM' -Now $script:sat0300 | Should -BeTrue
    }

    It 'blocks a time outside the window' {
        Test-SPSScheduleWindow -Time '2:00 AM to 4:00 AM' -Now $script:sat0500 | Should -BeFalse
    }

    It 'supports 24-hour time notation' {
        Test-SPSScheduleWindow -Time '02:00 to 04:00' -Now $script:sat0300 | Should -BeTrue
    }

    It 'requires both the day and the time to match when both are set' {
        # Right time but wrong day.
        Test-SPSScheduleWindow -Days @('sat') -Time '2:00 AM to 4:00 AM' -Now $script:mon0300 | Should -BeFalse
        # Right day and right time.
        Test-SPSScheduleWindow -Days @('sat') -Time '2:00 AM to 4:00 AM' -Now $script:sat0300 | Should -BeTrue
    }

    It 'throws on a malformed window' {
        { Test-SPSScheduleWindow -Time 'sometime tonight' -Now $script:sat0300 } | Should -Throw
    }

    It 'throws when the start is later than the end (crossing midnight)' {
        { Test-SPSScheduleWindow -Time '11:00 PM to 1:00 AM' -Now $script:sat0300 } | Should -Throw
    }

    It 'throws on an invalid day name instead of truncating it' {
        # 'saturn' must not be silently accepted as Saturday.
        { Test-SPSScheduleWindow -Days @('saturn') -Now $script:sat0300 } | Should -Throw
    }
}
