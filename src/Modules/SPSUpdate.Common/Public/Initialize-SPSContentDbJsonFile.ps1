function Initialize-SPSContentDbJsonFile {
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $Path
    )

    #Initialize jSON Object, variables and class
    New-Variable -Name jsonObject `
        -Description 'jSON object variable' `
        -Option AllScope `
        -Force

    $jsonObject = [PSCustomObject]@{}
    $tbSPContentDb1 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb2 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb3 = New-Object -TypeName System.Collections.ArrayList
    $tbSPContentDb4 = New-Object -TypeName System.Collections.ArrayList
    class SPDbContent {
        [System.String]$Name
        [System.String]$Server
        [System.String]$WebAppUrl
    }

    #Get all content databases
    $spAllDatabases = Get-SPContentDatabase -ErrorAction SilentlyContinue

    if ($null -ne $spAllDatabases) {
        # --- LPT (Longest Processing Time First) scheduling ---
        # Balance databases across 4 sequences by total DiskSizeRequired
        # rather than by count, so parallel upgrade workloads finish closer
        # to the same time.

        # 1. Sort databases by size descending
        $spSortedDatabases = $spAllDatabases |
            Sort-Object -Property DiskSizeRequired -Descending

        # 2. Track cumulative load (bytes) per sequence (index 0 = Seq1 .. 3 = Seq4)
        $sequenceLoad  = @(0.0, 0.0, 0.0, 0.0)
        $sequenceLists = @($tbSPContentDb1, $tbSPContentDb2, $tbSPContentDb3, $tbSPContentDb4)

        # 3. Assign each database to the sequence with the lowest current load
        foreach ($spDatabase in $spSortedDatabases) {
            $minLoad  = $sequenceLoad[0]
            $minIndex = 0
            for ($s = 1; $s -lt 4; $s++) {
                if ($sequenceLoad[$s] -lt $minLoad) {
                    $minLoad  = $sequenceLoad[$s]
                    $minIndex = $s
                }
            }
            [void]$sequenceLists[$minIndex].Add([SPDbContent]@{
                    Name      = $spDatabase.Name;
                    Server    = $spDatabase.Server;
                    WebAppUrl = $spDatabase.WebApplication.Url;
                })
            $sequenceLoad[$minIndex] += $spDatabase.DiskSizeRequired
        }

        # --- Distribution report (visible in transcript) ---
        $totalBytes = ($sequenceLoad | Measure-Object -Sum).Sum
        $totalMB    = [math]::Round($totalBytes / 1MB, 0)
        $dbCount    = @($spSortedDatabases).Count
        Write-Output '--- ContentDatabase Distribution Report ---'
        Write-Output ("Total : {0} database(s) | {1:N0} MB" -f $dbCount, $totalMB)
        for ($s = 0; $s -lt 4; $s++) {
            $loadMB = [math]::Round($sequenceLoad[$s] / 1MB, 0)
            $pct    = if ($totalBytes -gt 0) {
                [math]::Round($sequenceLoad[$s] / $totalBytes * 100, 1)
            }
            else { 0 }
            Write-Output ("  Sequence {0} : {1,3} database(s) | {2,7:N0} MB | {3,5:N1}%" `
                    -f ($s + 1), $sequenceLists[$s].Count, $loadMB, $pct)
        }
        Write-Output '-------------------------------------------'

        #Add each array to jsonObject
        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase1' `
            -Value $tbSPContentDb1

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase2' `
            -Value $tbSPContentDb2

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase3' `
            -Value $tbSPContentDb3

        $jsonObject | Add-Member -MemberType NoteProperty `
            -Name 'SPContentDatabase4' `
            -Value $tbSPContentDb4

        # Serialize once and write both the canonical file (consumed by SPSUpdate.ps1)
        # and a timestamped snapshot in the same folder so previous inventories are
        # retained for troubleshooting and rollback.
        $jsonPayload = $jsonObject | ConvertTo-Json
        $jsonPayload | Set-Content -Path $Path -Force

        try {
            $snapshotDir       = [System.IO.Path]::GetDirectoryName($Path)
            $snapshotBaseName  = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $snapshotExtension = [System.IO.Path]::GetExtension($Path)
            $snapshotTimestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
            $snapshotFileName  = '{0}_{1}{2}' -f $snapshotBaseName, $snapshotTimestamp, $snapshotExtension
            $snapshotPath      = if ([string]::IsNullOrEmpty($snapshotDir)) {
                $snapshotFileName
            }
            else {
                Join-Path -Path $snapshotDir -ChildPath $snapshotFileName
            }
            $jsonPayload | Set-Content -Path $snapshotPath -Force
            Write-Output "ContentDatabase inventory snapshot saved to: $snapshotPath"
        }
        catch {
            Write-Verbose -Message "Failed to write ContentDatabase inventory snapshot: $($_.Exception.Message)"
        }
    }
}
