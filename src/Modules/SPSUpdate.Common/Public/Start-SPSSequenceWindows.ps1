function Start-SPSSequenceWindows {
    <#
    .SYNOPSIS
        Launches the parallel content-database sequence runs in visible PowerShell windows.

    .DESCRIPTION
        Interactive alternative to the scheduled-task orchestration used by the Default action.
        Each sequence is started as a separate visible Windows PowerShell process
        (SPSUpdate.ps1 -Sequence N), so an operator running an attended patching campaign sees
        per-sequence progress live. The windows inherit the caller's identity, so the DPAPI
        secret is decrypted exactly as the scheduled tasks do when the session runs as the
        InstallAccount. Starts are staggered to avoid OWSTimer conflicts, mirroring the task path.

        The function returns the started process objects without waiting; the caller waits on
        them (and refreshes the dashboard) so the live-dashboard concern stays in the entry script.

    .PARAMETER ScriptPath
        Full path to SPSUpdate.ps1 (the script re-invokes itself with -Sequence N).

    .PARAMETER ConfigFile
        The configuration file passed through to each sequence run.

    .PARAMETER Count
        Number of parallel sequence windows to start (defaults to 4, matching the task path).

    .PARAMETER StartDelaySeconds
        Delay inserted between consecutive window starts to avoid OWSTimer conflicts. Defaults
        to a random 60-90s, matching the scheduled-task path.

    .PARAMETER PowerShellPath
        The PowerShell host used to run each window. Defaults to Windows PowerShell
        (powershell.exe) because SharePoint cmdlets require Windows PowerShell 5.1 and the
        SharePoint snap-in does not load on PowerShell 7.

    .EXAMPLE
        $procs = Start-SPSSequenceWindows -ScriptPath $fullScriptPath -ConfigFile $ConfigFile
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFile,

        [Parameter()]
        [ValidateRange(1, 16)]
        [System.Int32]
        $Count = 4,

        [Parameter()]
        [System.Int32]
        $StartDelaySeconds = -1,

        [Parameter()]
        [System.String]
        $PowerShellPath = 'powershell.exe'
    )

    $processes = [System.Collections.Generic.List[object]]::new()
    for ($i = 1; $i -le $Count; $i++) {
        $argumentList = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigFile `"$ConfigFile`" -Sequence $i -Verbose"
        if ($PSCmdlet.ShouldProcess("Sequence $i", "Start PowerShell window")) {
            $proc = Start-Process -FilePath $PowerShellPath -ArgumentList $argumentList -PassThru
            $processes.Add($proc)
            Write-Verbose -Message "Started sequence $i in a new PowerShell window (PID $($proc.Id))."

            # Stagger the next start to avoid OWSTimer conflicts, except after the last window.
            if ($i -lt $Count) {
                $delay = if ($StartDelaySeconds -ge 0) { $StartDelaySeconds } else { Get-Random -Minimum 60 -Maximum 91 }
                Write-Verbose -Message "Avoid conflicts with OWSTimer process - Pause $delay seconds before the next window."
                Start-Sleep -Seconds $delay
            }
        }
    }

    return $processes.ToArray()
}
