function Compare-SPSContentDbInventory {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    # Compares the cached ContentDatabase inventory with the content databases currently attached
    # to the farm. Name matching is case-insensitive. Read-only.
    if (-not (Test-Path -Path $Path)) {
        throw "ContentDatabase inventory file not found: $Path"
    }

    $inventory = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $inventoryNames = New-Object -TypeName 'System.Collections.Generic.List[System.String]'
    foreach ($prop in 'SPContentDatabase1', 'SPContentDatabase2', 'SPContentDatabase3', 'SPContentDatabase4') {
        if ($inventory.PSObject.Properties.Name -notcontains $prop) { continue }
        foreach ($db in @($inventory.$prop)) {
            if ($null -ne $db -and -not [string]::IsNullOrEmpty("$($db.Name)")) { $inventoryNames.Add("$($db.Name)") }
        }
    }

    $liveNames = New-Object -TypeName 'System.Collections.Generic.List[System.String]'
    foreach ($db in @(Get-SPContentDatabase -ErrorAction Stop)) {
        if ($null -ne $db -and -not [string]::IsNullOrEmpty("$($db.Name)")) { $liveNames.Add("$($db.Name)") }
    }

    $inventorySet = New-Object -TypeName 'System.Collections.Generic.HashSet[System.String]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $inventoryNames) { [void]$inventorySet.Add($n) }
    $liveSet = New-Object -TypeName 'System.Collections.Generic.HashSet[System.String]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $liveNames) { [void]$liveSet.Add($n) }

    $notInInventory = @($liveNames | Where-Object { -not $inventorySet.Contains($_) } | Sort-Object -Unique)
    $notInFarm = @($inventoryNames | Where-Object { -not $liveSet.Contains($_) } | Sort-Object -Unique)

    return [PSCustomObject]@{
        InventoryCount = $inventorySet.Count
        LiveCount      = $liveSet.Count
        NotInInventory = $notInInventory
        NotInFarm      = $notInFarm
        HasDrift       = ($notInInventory.Count -gt 0 -or $notInFarm.Count -gt 0)
    }
}
