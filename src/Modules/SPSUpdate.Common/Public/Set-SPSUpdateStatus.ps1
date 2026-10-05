function Set-SPSUpdateStatus {
    <#
        .SYNOPSIS
        Writes (upserts) a patching progress record into the shared status store.

        .DESCRIPTION
        Set-SPSUpdateStatus persists one "scope" of patching progress as a JSON file
        in the campaign folder of the status store (a UNC share shared by every farm
        server, or a local folder as a fallback). It is the building block of the
        near-real-time SPSUpdate dashboard.

        A scope is identified by Server + Scope (e.g. APP1 + 'Sequence1'). Each writer
        owns a distinct scope file, so the four parallel sequence tasks, the local
        ProductUpdate on each server and the master (which records the wizard state of
        every server) never write the same file concurrently. Writes are atomic
        (written to a temporary file then moved into place) so a reader never sees a
        half-written document, with a short retry to absorb transient UNC sharing
        violations.

        Optionally upserts a single item inside the scope (e.g. a database name or a
        setup file) with its own state / detail / exit code, so the dashboard can show
        per-database or per-binary progress.

        .PARAMETER CampaignPath
        Folder of the current patching campaign (for example
        <StatusStorePath>\<App>-<Env>-<Farm>). Created if missing.

        .PARAMETER Scope
        Scope key that identifies the owning writer and names the file
        (<Server>__<Scope>.json). Examples: 'ProductUpdate', 'Sequence1', 'Wizard'.

        .PARAMETER Phase
        Logical phase the scope belongs to, used to group the dashboard.

        .PARAMETER Server
        Server the scope relates to. Defaults to the local computer name.

        .PARAMETER State
        Scope-level state.

        .PARAMETER Detail
        Free-form scope-level detail.

        .PARAMETER Percent
        Optional scope-level completion percentage (0-100).

        .PARAMETER Item
        Optional item name to upsert inside the scope (e.g. a database or a setup file).

        .PARAMETER ItemState
        State of the upserted item.

        .PARAMETER ItemDetail
        Detail of the upserted item.

        .PARAMETER ExitCode
        Optional exit code recorded on the item.

        .PARAMETER Build
        Optional installed SharePoint product build for the server (dashboard metadata).

        .PARAMETER PatchStatus
        Optional SharePoint patch/upgrade status baseline for the server (for example
        'No Action Required'), as returned by Get-SPSServersPatchStatus.

        .PARAMETER Role
        Optional farm role of the server (for example 'Application', 'WebFrontEnd', 'Search').

        .PARAMETER SeedIfAbsent
        Baseline/enrichment mode used by the master when pre-filling the dashboard. When the scope
        does not exist yet it is created from the supplied metadata; when it already exists (a worker
        owns it) only the farm metadata the master knows (Role, PatchStatus, and Build only when none
        is recorded yet) is updated - the worker's State, Detail, Percent, CompletedAt and Items are
        never overwritten. The absence check and the write happen inside the same per-scope lock as
        every other writer, so a worker starting the scope concurrently is not clobbered.

        .EXAMPLE
        Set-SPSUpdateStatus -CampaignPath $c -Scope 'Sequence1' -Phase 'Upgrade' -State 'Running' -Item 'DB_A' -ItemState 'Done' -ItemDetail 'upgraded' -ExitCode 0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CampaignPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Scope,

        [Parameter()]
        [ValidateSet('ProductUpdate', 'Reboot', 'Mount', 'Upgrade', 'Sequence', 'Wizard', 'SideBySide')]
        [System.String]
        $Phase = 'Sequence',

        [Parameter()]
        [System.String]
        $Server = $env:COMPUTERNAME,

        [Parameter()]
        [ValidateSet('Pending', 'Running', 'Done', 'Failed', 'Warning', 'Skipped')]
        [System.String]
        $State,

        [Parameter()]
        [System.String]
        $Detail,

        [Parameter()]
        [System.Nullable[int]]
        $Percent,

        [Parameter()]
        [System.String]
        $Item,

        [Parameter()]
        [ValidateSet('Pending', 'Running', 'Done', 'Failed', 'Warning', 'Skipped')]
        [System.String]
        $ItemState,

        [Parameter()]
        [System.String]
        $ItemDetail,

        [Parameter()]
        [System.Nullable[int]]
        $ExitCode,

        [Parameter()]
        [System.String]
        $Build,

        [Parameter()]
        [System.String]
        $PatchStatus,

        [Parameter()]
        [System.String]
        $Role,

        [Parameter()]
        [switch]
        $SeedIfAbsent
    )

    if (-not (Test-Path -Path $CampaignPath)) {
        $null = New-Item -Path $CampaignPath -ItemType Directory -Force
    }

    $safeServer = ($Server -replace '[^A-Za-z0-9_.-]', '_')
    $safeScope = ($Scope -replace '[^A-Za-z0-9_.-]', '_')
    $fileName = '{0}__{1}.json' -f $safeServer, $safeScope
    $filePath = Join-Path -Path $CampaignPath -ChildPath $fileName
    $now = (Get-Date).ToString('o')

    # Acquire a best-effort cross-machine advisory lock on this scope so the read-modify-write is
    # not interleaved with another writer of the SAME file (the master's baseline enrichment and the
    # owning server's worker can both target e.g. APP2__ProductUpdate.json from different machines).
    # A sibling '.lock' file created with CreateNew is atomic over SMB; if it cannot be taken within
    # the retry budget (for example a stale lock from a crashed writer) we proceed anyway so the
    # dashboard never deadlocks - the atomic temp-file move still prevents torn reads.
    $lockPath = '{0}.lock' -f $filePath
    $lockStream = $null
    $lockAcquired = $false
    $lockAttempts = 0
    while (-not $lockAcquired -and $lockAttempts -lt 40) {
        $lockAttempts++
        try {
            $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $lockAcquired = $true
        }
        catch {
            Start-Sleep -Milliseconds (40 + (Get-Random -Maximum 60))
        }
    }

    try {
        # Load the existing scope record (if any) so items accumulate across calls.
        $record = $null
        if (Test-Path -Path $filePath) {
            try {
                $raw = Get-Content -Path $filePath -Raw -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $record = $raw | ConvertFrom-Json -ErrorAction Stop
                }
            }
            catch {
                Write-Verbose -Message "Set-SPSUpdateStatus: could not read existing '$filePath', starting fresh: $($_.Exception.Message)"
            }
        }
        $recordExisted = ($null -ne $record)

        if ($null -eq $record) {
            $record = [PSCustomObject]@{
                Server      = $Server
                Scope       = $Scope
                Phase       = $Phase
                State       = 'Pending'
                Detail      = ''
                Percent     = $null
                Role        = ''
                Build       = ''
                PatchStatus = ''
                StartedAt   = $now
                UpdatedAt   = $now
                CompletedAt = $null
                Items       = @()
            }
        }

        # Ensure fields added after a record was first written exist on records loaded from older
        # JSON (ConvertFrom-Json only materializes the properties that were present on disk).
        foreach ($prop in 'Role', 'Build', 'PatchStatus', 'CompletedAt') {
            if (-not $record.PSObject.Properties[$prop]) {
                $record | Add-Member -NotePropertyName $prop -NotePropertyValue $null
            }
        }

        $record.Server = $Server
        $record.Scope = $Scope
        $record.Phase = $Phase
        $record.UpdatedAt = $now

        if ($SeedIfAbsent -and $recordExisted) {
            # Baseline enrichment of a worker-owned scope: update only the farm metadata the master
            # knows and never the worker's lifecycle fields. Build is set only when none is recorded
            # yet, preserving a worker's installed-CU build.
            if ($PSBoundParameters.ContainsKey('Role')) { $record.Role = $Role }
            if ($PSBoundParameters.ContainsKey('PatchStatus')) { $record.PatchStatus = $PatchStatus }
            if ($PSBoundParameters.ContainsKey('Build') -and [string]::IsNullOrEmpty("$($record.Build)")) { $record.Build = $Build }
        }
        else {
            if ($PSBoundParameters.ContainsKey('State')) { $record.State = $State }
            if ($PSBoundParameters.ContainsKey('Detail')) { $record.Detail = $Detail }
            if ($PSBoundParameters.ContainsKey('Percent')) { $record.Percent = $Percent }
            if ($PSBoundParameters.ContainsKey('Role')) { $record.Role = $Role }
            if ($PSBoundParameters.ContainsKey('Build')) { $record.Build = $Build }
            if ($PSBoundParameters.ContainsKey('PatchStatus')) { $record.PatchStatus = $PatchStatus }
            # Stamp the completion time the first time the scope reaches a terminal success state, and
            # clear it if the scope is re-attempted (back to Pending/Running) so a later run does not
            # show a stale completion date. Repeated terminal writes keep the original stamp.
            if ($PSBoundParameters.ContainsKey('State')) {
                if ($State -eq 'Done' -or $State -eq 'Skipped') {
                    if ($null -eq $record.CompletedAt) { $record.CompletedAt = $now }
                }
                elseif ($State -eq 'Pending' -or $State -eq 'Running') {
                    $record.CompletedAt = $null
                }
            }

            # Upsert the optional item (not used by baseline enrichment of an existing scope).
            if ($PSBoundParameters.ContainsKey('Item') -and -not [string]::IsNullOrEmpty($Item)) {
                $items = @($record.Items)
                $existing = $items | Where-Object { $_.Name -eq $Item } | Select-Object -First 1
                if ($null -eq $existing) {
                    $existing = [PSCustomObject]@{
                        Name      = $Item
                        State     = 'Pending'
                        Detail    = ''
                        ExitCode  = $null
                        UpdatedAt = $now
                    }
                    $items += $existing
                }
                $existing.UpdatedAt = $now
                if ($PSBoundParameters.ContainsKey('ItemState')) { $existing.State = $ItemState }
                if ($PSBoundParameters.ContainsKey('ItemDetail')) { $existing.Detail = $ItemDetail }
                if ($PSBoundParameters.ContainsKey('ExitCode')) { $existing.ExitCode = $ExitCode }
                $record.Items = $items
            }
        }

        if (-not $PSCmdlet.ShouldProcess($filePath, 'Write SPSUpdate status')) {
            return $filePath
        }

        $json = $record | ConvertTo-Json -Depth 6
        $tmpPath = '{0}.tmp.{1}' -f $filePath, ([guid]::NewGuid().ToString('N'))
        $encoding = New-Object System.Text.UTF8Encoding($false)

        $attempts = 0
        $written = $false
        while (-not $written -and $attempts -lt 5) {
            $attempts++
            try {
                [System.IO.File]::WriteAllText($tmpPath, $json, $encoding)
                Move-Item -Path $tmpPath -Destination $filePath -Force -ErrorAction Stop
                $written = $true
            }
            catch {
                if (Test-Path -Path $tmpPath) { Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue }
                if ($attempts -ge 5) {
                    Write-Warning -Message "Set-SPSUpdateStatus: failed to write '$filePath' after $attempts attempts: $($_.Exception.Message)"
                }
                else {
                    Start-Sleep -Milliseconds (150 * $attempts)
                }
            }
        }

        return $filePath
    }
    finally {
        # Release the advisory lock (close the handle, then remove the sibling lock file).
        if ($null -ne $lockStream) {
            try { $lockStream.Close(); $lockStream.Dispose() } catch { Write-Verbose -Message "Set-SPSUpdateStatus: lock handle cleanup failed: $($_.Exception.Message)" }
        }
        if ($lockAcquired) {
            Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}
