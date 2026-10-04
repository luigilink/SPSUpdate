function Start-SPSSequenceWindows {
    <#
    .SYNOPSIS
        Runs the parallel content-database sequences in visible PowerShell windows.

    .DESCRIPTION
        Interactive alternative to the scheduled-task orchestration used by the Default action.
        Each sequence is launched as a separate visible Windows PowerShell process
        (SPSUpdate.ps1 -Sequence N) so an operator running an attended patching campaign sees
        per-sequence progress live. The windows run as the current user (who is already a farm
        administrator when running SPSUpdate interactively); the content-database cmdlets run under
        that identity, so no InstallAccount credential is involved in the sequences.

        Starts are staggered to avoid OWSTimer conflicts and the caller's dashboard refresh is
        invoked (via DashboardCallback) between starts and while waiting, so the live dashboard
        stays current. Launch failures are terminating, and a non-zero child exit code marks the
        sequence as failed in the returned result so the caller does not silently continue.

    .PARAMETER ScriptPath
        Full path to SPSUpdate.ps1 (the script re-invokes itself with -Sequence N).

    .PARAMETER ConfigFile
        The configuration file passed through to each sequence run.

    .PARAMETER Count
        Number of parallel sequences to launch (1-4, defaults to 4, matching the task path and
        the SPSUpdate.ps1 -Sequence range).

    .PARAMETER StartDelaySeconds
        Delay between consecutive starts to avoid OWSTimer conflicts. Negative (default) means a
        random 60-90s, matching the scheduled-task path.

    .PARAMETER PollSeconds
        Dashboard refresh / poll interval, in seconds, during the stagger and the wait (default 10).

    .PARAMETER DashboardCallback
        Optional script block invoked to refresh the live dashboard between starts and while
        waiting. It runs in its defining scope, so it can call the entry script's dashboard writer.

    .PARAMETER PowerShellPath
        PowerShell host used to run each window. Defaults to Windows PowerShell (powershell.exe)
        because the SharePointServer module (SharePoint Server Subscription Edition) targets the
        full .NET Framework and runs on Windows PowerShell 5.1, not PowerShell 7.

    .OUTPUTS
        A PSCustomObject with Processes (the started processes) and FailedSequences (the sequence
        numbers whose window returned a non-zero exit code).

    .EXAMPLE
        $r = Start-SPSSequenceWindows -ScriptPath $p -ConfigFile $c -DashboardCallback { Write-SPSDashboard }
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFile,

        [Parameter()]
        [ValidateRange(1, 4)]
        [System.Int32]
        $Count = 4,

        [Parameter()]
        [System.Int32]
        $StartDelaySeconds = -1,

        [Parameter()]
        [ValidateRange(1, 600)]
        [System.Int32]
        $PollSeconds = 10,

        [Parameter()]
        [System.Management.Automation.ScriptBlock]
        $DashboardCallback,

        [Parameter()]
        [System.String]
        $PowerShellPath = 'powershell.exe'
    )

    $launched = [System.Collections.Generic.List[object]]::new()
    for ($i = 1; $i -le $Count; $i++) {
        if (-not $PSCmdlet.ShouldProcess("Sequence $i", "Start PowerShell window")) {
            continue
        }

        $argumentList = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigFile `"$ConfigFile`" -Sequence $i -Verbose"
        # Terminating on launch failure: a null process would otherwise be silently skipped while
        # the sequence is reported as started and the run would continue without it.
        $proc = Start-Process -FilePath $PowerShellPath -ArgumentList $argumentList -PassThru -ErrorAction Stop
        # Track the actual sequence number with the process so a skipped (declined) sequence never
        # shifts the numbers reported in FailedSequences.
        $launched.Add([PSCustomObject]@{ Sequence = $i; Process = $proc })
        Write-Verbose -Message "Started sequence $i in a new PowerShell window (PID $($proc.Id))."
        if ($DashboardCallback) { & $DashboardCallback }

        # Stagger the next start to avoid OWSTimer conflicts (except after the last window),
        # refreshing the dashboard every PollSeconds during the pause.
        if ($i -lt $Count) {
            $delay = if ($StartDelaySeconds -ge 0) { $StartDelaySeconds } else { Get-Random -Minimum 60 -Maximum 91 }
            $waited = 0
            while ($waited -lt $delay) {
                $chunk = [System.Math]::Min($PollSeconds, ($delay - $waited))
                Start-Sleep -Seconds $chunk
                $waited += $chunk
                if ($DashboardCallback) { & $DashboardCallback }
            }
        }
    }

    # Wait for every window to exit, refreshing the dashboard from the shared status store.
    $running = @($launched | Where-Object { $_.Process -and -not $_.Process.HasExited })
    while ($running.Count -gt 0) {
        if ($DashboardCallback) { & $DashboardCallback }
        Start-Sleep -Seconds $PollSeconds
        $running = @($launched | Where-Object { $_.Process -and -not $_.Process.HasExited })
    }
    if ($DashboardCallback) { & $DashboardCallback }

    # A non-zero exit code (failed worker, or a window closed by the operator) must not be treated
    # as success; surface the actual sequence number so the caller can log it.
    $failed = [System.Collections.Generic.List[int]]::new()
    foreach ($entry in $launched) {
        $exit = $entry.Process.ExitCode
        if ($null -ne $exit -and $exit -ne 0) {
            $failed.Add($entry.Sequence)
        }
    }

    return [PSCustomObject]@{
        Processes       = @($launched.Process)
        FailedSequences = $failed.ToArray()
    }
}
