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
        [ValidateSet('ProductUpdate', 'Mount', 'Upgrade', 'Sequence', 'Wizard', 'SideBySide')]
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
        $ExitCode
    )

    if (-not (Test-Path -Path $CampaignPath)) {
        $null = New-Item -Path $CampaignPath -ItemType Directory -Force
    }

    $safeServer = ($Server -replace '[^A-Za-z0-9_.-]', '_')
    $safeScope = ($Scope -replace '[^A-Za-z0-9_.-]', '_')
    $fileName = '{0}__{1}.json' -f $safeServer, $safeScope
    $filePath = Join-Path -Path $CampaignPath -ChildPath $fileName
    $now = (Get-Date).ToString('o')

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

    if ($null -eq $record) {
        $record = [PSCustomObject]@{
            Server    = $Server
            Scope     = $Scope
            Phase     = $Phase
            State     = 'Pending'
            Detail    = ''
            Percent   = $null
            StartedAt = $now
            UpdatedAt = $now
            Items     = @()
        }
    }

    $record.Server = $Server
    $record.Scope = $Scope
    $record.Phase = $Phase
    $record.UpdatedAt = $now
    if ($PSBoundParameters.ContainsKey('State')) { $record.State = $State }
    if ($PSBoundParameters.ContainsKey('Detail')) { $record.Detail = $Detail }
    if ($PSBoundParameters.ContainsKey('Percent')) { $record.Percent = $Percent }

    # Upsert the optional item.
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
