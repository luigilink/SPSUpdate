function Start-SPSSequenceWindow {
    <#
    .SYNOPSIS
        Launches one parallel content-database sequence run in a visible PowerShell window.

    .DESCRIPTION
        Interactive alternative to the scheduled-task orchestration used by the Default action.
        Each sequence is started as a separate visible Windows PowerShell process
        (SPSUpdate.ps1 -Sequence N) so an operator running an attended patching campaign sees
        per-sequence progress live. The window inherits the caller's identity, so the DPAPI
        secret is decrypted exactly as the scheduled tasks do when the session runs as the
        InstallAccount.

        This function launches a single window and returns its process object without waiting.
        The caller loops over the sequences so it can stagger the starts (to avoid OWSTimer
        conflicts) and refresh the live dashboard between them, then waits on the processes.

    .PARAMETER ScriptPath
        Full path to SPSUpdate.ps1 (the script re-invokes itself with -Sequence N).

    .PARAMETER ConfigFile
        The configuration file passed through to the sequence run.

    .PARAMETER Sequence
        The sequence number (1-based) passed to SPSUpdate.ps1 -Sequence.

    .PARAMETER PowerShellPath
        The PowerShell host used to run the window. Defaults to Windows PowerShell
        (powershell.exe) because SharePoint cmdlets require Windows PowerShell 5.1 and the
        SharePoint snap-in does not load on PowerShell 7.

    .EXAMPLE
        $proc = Start-SPSSequenceWindow -ScriptPath $fullScriptPath -ConfigFile $ConfigFile -Sequence 1
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Diagnostics.Process])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFile,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 16)]
        [System.Int32]
        $Sequence,

        [Parameter()]
        [System.String]
        $PowerShellPath = 'powershell.exe'
    )

    $argumentList = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigFile `"$ConfigFile`" -Sequence $Sequence -Verbose"
    if ($PSCmdlet.ShouldProcess("Sequence $Sequence", "Start PowerShell window")) {
        $proc = Start-Process -FilePath $PowerShellPath -ArgumentList $argumentList -PassThru
        Write-Verbose -Message "Started sequence $Sequence in a new PowerShell window (PID $($proc.Id))."
        return $proc
    }
}
