function Start-SPSScheduledTask {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint'
    )

    $normalizedTaskPath = if ($TaskPath.StartsWith('\')) {
        $TaskPath
    }
    else {
        "\$TaskPath"
    }
    if (-not $normalizedTaskPath.EndsWith('\')) {
        $normalizedTaskPath = "$normalizedTaskPath\"
    }

    $getScheduledTask = Get-ScheduledTask -TaskName $Name -TaskPath $normalizedTaskPath -ErrorAction SilentlyContinue
    if (-not $getScheduledTask) {
        throw "Scheduled Task $Name does not exist in $TaskPath Task Path"
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Start scheduled task')) {
        Start-ScheduledTask -TaskName $Name `
            -TaskPath $normalizedTaskPath `
            -ErrorAction Stop
    }

    $startedTask = Get-ScheduledTask -TaskName $Name -TaskPath $normalizedTaskPath -ErrorAction Stop
    return [PSCustomObject]@{
        Name     = $Name
        TaskPath = $normalizedTaskPath
        State    = $startedTask.State
    }
}
