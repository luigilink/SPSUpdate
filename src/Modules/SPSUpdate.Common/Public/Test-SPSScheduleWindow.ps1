function Test-SPSScheduleWindow {
    <#
        .SYNOPSIS
        Tests whether the current moment falls inside an allowed schedule window.

        .DESCRIPTION
        Test-SPSScheduleWindow gates a time-sensitive action (binary install, reboot)
        on an optional day-of-week list and an optional daily time window, mirroring the
        BinaryInstallDays / BinaryInstallTime pattern of the SharePointDsc SPProductUpdate
        resource. Both constraints are optional and independent:

        - When no Days and no Time are supplied, the window is always open (returns $true).
        - When Days is supplied, the current day (short name mon/tue/.../sun) must be in
          the list.
        - When Time is supplied ("<start> to <end>", for example '2:00 AM to 4:00 AM' or
          '23:00 to 23:30'), the current time must fall inside the window.

        The time window is same-day only: the start must not be later than the end, so
        windows that cross midnight are rejected (throwing a clear error). A malformed
        window throws rather than silently allowing the action, so the caller fails closed.

        .PARAMETER Days
        Allowed days as short names (mon, tue, wed, thu, fri, sat, sun). Case-insensitive.
        Empty or $null means "any day".

        .PARAMETER Time
        Allowed daily window as '<start> to <end>'. Empty or $null means "any time".

        .PARAMETER Now
        Reference moment used for the comparison. Defaults to the current date/time.
        Exposed mainly for deterministic testing.

        .EXAMPLE
        Test-SPSScheduleWindow -Days @('sat','sun') -Time '2:00 AM to 4:00 AM'

        .EXAMPLE
        Test-SPSScheduleWindow -Time '23:00 to 23:45' -Now ([datetime]'2026-09-26T23:10:00')
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $Days,

        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [System.String]
        $Time,

        [Parameter()]
        [System.DateTime]
        $Now = (Get-Date)
    )

    # No day and no time restriction: the window is always open.
    if (($null -eq $Days -or $Days.Count -eq 0) -and [string]::IsNullOrWhiteSpace($Time)) {
        return $true
    }

    # Day-of-week gate.
    if ($null -ne $Days -and $Days.Count -gt 0) {
        $currentDay = $Now.DayOfWeek.ToString().ToLower().Substring(0, 3)
        $allowedDays = @($Days | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                $trimmed = $_.Trim().ToLower()
                $trimmed.Substring(0, [System.Math]::Min(3, $trimmed.Length))
            })
        if ($allowedDays -notcontains $currentDay) {
            return $false
        }
    }

    # Time-window gate.
    if (-not [string]::IsNullOrWhiteSpace($Time)) {
        $parts = [regex]::Split($Time, '\s+to\s+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($parts.Count -ne 2) {
            throw "Schedule time window is incorrectly formatted: '$Time'. Expected '<start> to <end>', for example '2:00 AM to 4:00 AM'."
        }

        $startParsed = [datetime]::MinValue
        $endParsed = [datetime]::MinValue
        if (-not [datetime]::TryParse($parts[0].Trim(), [ref]$startParsed)) {
            throw "Schedule time window has an invalid start time: '$($parts[0].Trim())'."
        }
        if (-not [datetime]::TryParse($parts[1].Trim(), [ref]$endParsed)) {
            throw "Schedule time window has an invalid end time: '$($parts[1].Trim())'."
        }

        # Normalize both bounds onto the reference date so the comparison is date-agnostic.
        $startOnNow = $Now.Date.Add($startParsed.TimeOfDay)
        $endOnNow = $Now.Date.Add($endParsed.TimeOfDay)

        if ($startOnNow -gt $endOnNow) {
            throw "Schedule time window start ('$($parts[0].Trim())') cannot be later than end ('$($parts[1].Trim())'). Windows crossing midnight are not supported."
        }

        if ($Now -lt $startOnNow -or $Now -gt $endOnNow) {
            return $false
        }
    }

    return $true
}
