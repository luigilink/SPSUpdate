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
| `Action` | (Optional) `Install`, `Uninstall`, `Default`, `ProductUpdate`, `InitContentDB`, `ResetStatus` or `ConfirmReboot`. `Install`/`Uninstall` manage the scheduled tasks and the stored secret (`Install` requires `InstallAccount`). `ProductUpdate` installs the binaries locally (and, when the `Reboot` block is enabled, reboots the server automatically — see [Automatic reboot after a CU install](#automatic-reboot-after-a-cu-install)). `InitContentDB` (re)generates the ContentDatabase inventory JSON. `ResetStatus` clears the status store campaign and writes an initial live dashboard so you can open it in a browser before patching begins (see [Near real-time patching dashboard](#near-real-time-patching-dashboard)). `ConfirmReboot` is an internal status-only action run at boot by the one-shot reboot-confirmation task. Defaults to `Default`. |
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

> Since v5.0.0 SPSUpdate is Subscription Edition only. To run `InitContentDB` on a
> **SharePoint Server 2019 source farm** during a 2019 → Subscription Edition migration, use
> the previous major release [v4.2.0](https://github.com/luigilink/SPSUpdate/releases/tag/v4.2.0).

It also writes a self-contained HTML report of the inventory under `Results\` (see below).

### Example 7: ResetStatus (prepare the live dashboard)

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action ResetStatus
```

This clears the status store campaign folder and writes an empty **live dashboard**
(`_dashboard.html`) you can open in a browser before the patching campaign starts. See
[Near real-time patching dashboard](#near-real-time-patching-dashboard) for the full workflow.

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

## Near real-time patching dashboard

When a status store is configured, SPSUpdate records the progress of every phase
(ProductUpdate per server, the four mount/upgrade sequences, the Configuration Wizard
per server, and side-by-side) into a shared location, and the master assembles a live
HTML dashboard you can open in a browser while patching runs.

### Configure the status store

Set `StatusStorePath` in the environment config to a UNC share writable by the
InstallAccount from every farm server:

```powershell
StatusStorePath = '\\fileserver\spsupdate-status'
```

If left empty, SPSUpdate falls back to a local `Results\status` folder. In that case the
master still shows the mount/upgrade/wizard phases, but ProductUpdate runs launched on the
other servers are not captured centrally (they would each write to their own local folder).

The status files of one patching campaign live under
`<StatusStorePath>\<App>-<Env>-<Farm>\`, and the dashboard is written there as
`_dashboard.html`.

> [!IMPORTANT]
> **The InstallAccount (the scheduled-task service account) must have Modify rights on
> the share — both the SMB share permission and the NTFS permission.** The four
> upgrade/mount sequence tasks run as that account, so if it cannot write to the store the
> sequences silently fail to publish their status and the **Content database upgrade phase
> never appears on the dashboard** (only the ProductUpdate and Wizard sections, written by
> the interactive/master run, show up). The ProductUpdate and Default runs you launch
> interactively write under your own account, which can mask the problem during testing.
> `Test-SPSUpdateReadiness.ps1` probes write access both as the current user **and** as the
> InstallAccount to catch this up front.

### Run a patched campaign with the dashboard

1. **Reset** the campaign once (clears any previous run):

   ```powershell
   .\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action ResetStatus
   ```

2. Open `\<StatusStorePath>\<App>-<Env>-<Farm>\_dashboard.html` in a browser. It
   auto-refreshes every 15 seconds while the campaign is in progress.

3. Install the binaries on **each** server (each writes its ProductUpdate progress to the
   share):

   ```powershell
   .\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action ProductUpdate
   ```

4. Run the master upgrade on the master server. It regenerates the dashboard as the four
   sequences, the Configuration Wizard and the side-by-side step progress, and turns the
   auto-refresh off with a final state when finished:

   ```powershell
   .\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
   ```

The dashboard shows the overall state, per-server / per-sequence progress, per-database and
per-binary item states with exit codes, and a completion percentage for each sequence.

## Automatic reboot after a CU install

A cumulative update frequently requires a reboot before the Configuration Wizard can run
(the installer returns exit code `17022`). SPSUpdate can perform that reboot automatically,
once, when the optional `Reboot` block is enabled in the config (it is **off by default**):

```powershell
Reboot = @{
    Enable   = $true
    Force    = $false                     # reboot strictly on exit code 17022
    Schedule = @{ Days = @('sat','sun'); Time = '3:00 AM to 4:00 AM' }
}
```

When enabled, at the end of `-Action ProductUpdate` on a server:

1. If the install returned `17022` (or `Reboot.Force` is set) and the current time is
   inside the optional `Reboot.Schedule` window, SPSUpdate marks the **Reboot** phase as
   *Running* on the dashboard ("Automatic Reboot launched, check the server in a few
   minutes") and logs a Windows Event Log entry (source `Restart-SPSServer`, ID 3010).
2. It registers a one-shot boot task (`SPSUpdate-RebootConfirm`, running as the
   InstallAccount) and restarts the server.
3. When the server comes back, that task runs `-Action ConfirmReboot`, which marks the
   Reboot phase as *Done* ("Server back online after automatic reboot"), logs the
   completion and removes itself.

The reboot is triggered **only** by the installer exit code, never by Windows
pending-reboot registry markers (which commonly stay set on production farms), so it
happens at most once per patching campaign. Outside the schedule window the dashboard
shows the reboot as *Pending*; with `Reboot.Enable = $false` no reboot is attempted.

Use `-WhatIf` on the `ProductUpdate` run for a dry run that logs "would reboot" without
restarting.

> [!WARNING]
> Reboots are **per-server**. On a farm, do not reboot the sole Distributed Cache host or
> the last available WFE at the same time — run `ProductUpdate` one server at a time and
> keep the farm quorum in mind.

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

## Pre-flight readiness check

`Test-SPSUpdateReadiness.ps1` validates the environment before a run (read-only). It checks
the module import, the config keys, the DPAPI secret, elevation, the status store
reachability and write access, and the per-server WinRM/CredSSP reachability:

```powershell
.\Test-SPSUpdateReadiness.ps1 -ConfigFile 'Config\CONTOSO-PROD-CONTENT.psd1'
```

It exits non-zero when any check fails, so it can gate an automated rollout.

## Support

For issues or questions, open an [issue](https://github.com/luigilink/SPSUpdate/issues) or
refer to the project documentation.
