# Usage Guide for `SPSUpdate.ps1`

## Overview

`SPSUpdate.ps1` installs SharePoint cumulative updates, mounts/upgrades content databases
in parallel and runs the post-setup Configuration Wizard (PSConfig) across the farm. Shared
logic lives in the `SPSUpdate.Common` module; the script just orchestrates it.

## Prerequisites

- PowerShell 5.1 or later.
- Administrator rights and access to the SharePoint farm.
- The package extracted on each SharePoint server (`SPSUpdate.ps1`, `Config\`, `Modules\`).
- Cumulative update files copied on each server (for `ProductUpdate`).

## Parameters

| Parameter | Description |
| --- | --- |
| `ConfigFile` | Path to the environment configuration file (`*.psd1`). **Required.** |
| `Action` | (Optional) `Install`, `Uninstall`, `Default`, `ProductUpdate` or `InitContentDB`. `Install`/`Uninstall` manage the scheduled tasks and the stored secret (`Install` requires `InstallAccount`). `ProductUpdate` installs the binaries locally. `InitContentDB` (re)generates the ContentDatabase inventory JSON. Defaults to `Default`. |
| `Sequence` | (Optional, 1–4) Internal: selects which content-database group a parallel scheduled task processes. |
| `InstallAccount` | (Optional) Required with `-Action Install`. The service account stored in `secrets.psd1`. |

## Examples

### Example 1: Default usage

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
```

### Example 2: Sequence (internal, run by the scheduled tasks)

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Sequence 1
```

### Example 3: Installation

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action Install -InstallAccount (Get-Credential)
```

### Example 4: Uninstallation

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action Uninstall
```

### Example 5: ProductUpdate

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action ProductUpdate
```

### Example 6: InitContentDB (source farm)

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action InitContentDB
```

This (re)generates the ContentDatabase inventory JSON file
(`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`) for the local farm. It
is typically used on the source farm before a farm upgrade (for example SharePoint Server
2019 → Subscription Edition) so the inventory can be copied to the target farm and consumed
by the `MountContentDatabase` flow.

It also writes a self-contained HTML report of the inventory under `Results\` (see below).

## ContentDatabase inventory report

Whenever the inventory JSON is (re)generated — by `-Action InitContentDB`, or by the
Default master run when it first primes the inventory — SPSUpdate also writes a
self-contained HTML report next to the `Logs\` and `Config\` folders:

```
Results\<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.html
```

The report is dependency-free (no internet required) and shows:

- summary cards: total content databases, total size (MB), and the balance spread across the four sequences;
- the per-sequence distribution (count / size / percentage) reflecting the Longest-Processing-Time-First balancing;
- a sortable, filterable table of every database with its sequence, server, web application and size.

Inventories generated before v4.1.0 have no size information; the report still renders and
falls back to distributing by database count. You can also generate the report on demand
from an existing inventory with the public function:

```powershell
Import-Module .\Modules\SPSUpdate.Common\SPSUpdate.Common.psd1
Export-SPSUpdateDbReport -InputFile '.\Config\contoso-PROD-CONTENT-ContentDBs.json' `
    -OutputFile '.\Results\contoso-PROD-CONTENT-ContentDBs.html' `
    -EnvName 'PROD' -AppCode 'contoso' -FarmName 'CONTENT'
```

## How a full run works (`Default`)

1. Reads the `InstallAccount` credential from `secrets.psd1` (DPAPI).
2. If `UpgradeContentDatabase` or `MountContentDatabase` is on, registers and starts four
   `SPSUpdate-Sequence1..4` scheduled tasks that process the content-database groups in
   parallel (the groups are balanced by size using a Longest-Processing-Time heuristic),
   then waits for all four to finish.
3. Runs PSConfig on the local (master) server when a patch action is required, then on each
   remote server over CredSSP.
4. Configures the side-by-side token and copies side-by-side files (when enabled).

## Logging

Each run starts a transcript under `Logs\` (the file name encodes the application,
environment and — when relevant — the sequence or action). The ContentDatabase inventory
HTML report is written under `Results\`. Lifecycle and error events are also written to the
dedicated **`SPSUpdate` Windows Event Log** via `Add-SPSUpdateEvent`.

## Error handling

- Ensure the account running the script has administrator rights and access to the farm.
- A missing secret raises a clear error pointing you to `-Action Install`.

## Notes

- Test the script in a non-production environment before deploying it widely.

## Support

For issues or questions, open an [issue](https://github.com/luigilink/SPSUpdate/issues) or
refer to the project documentation.
