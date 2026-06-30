function Get-SPSUpdateStatus {
    <#
        .SYNOPSIS
        Reads and merges every patching progress record of a campaign.

        .DESCRIPTION
        Get-SPSUpdateStatus reads all scope files (`*__*.json`) written by
        Set-SPSUpdateStatus in the campaign folder and returns them as an array of
        scope objects (Server, Scope, Phase, State, Detail, Percent, StartedAt,
        UpdatedAt, Items). It is the data source for Export-SPSUpdateProgressReport.

        Files that are missing, empty or momentarily unreadable (being written) are
        skipped silently so a partially captured campaign never throws. Temporary
        files (`*.tmp.*`) are ignored.

        .PARAMETER CampaignPath
        Folder of the patching campaign to read (for example
        <StatusStorePath>\<App>-<Env>-<Farm>).

        .EXAMPLE
        Get-SPSUpdateStatus -CampaignPath $c | Sort-Object Server, Scope
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CampaignPath
    )

    if (-not (Test-Path -Path $CampaignPath)) {
        return @()
    }

    $files = Get-ChildItem -Path $CampaignPath -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.tmp.*' }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        try {
            $raw = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $record = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $record) {
                $records.Add($record)
            }
        }
        catch {
            Write-Verbose -Message "Get-SPSUpdateStatus: skipping unreadable '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    return $records.ToArray()
}
