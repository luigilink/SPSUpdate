# Configuration

SPSUpdate is driven by two PowerShell data files in the `Config\` folder:

- a per-farm **environment config** (`*.psd1`) — hand-edited, gitignored;
- a **secret store** (`secrets.psd1`) — DPAPI-encrypted, gitignored, never committed.

Only the `*.example.psd1` templates are tracked in source control.

## Environment configuration (`*.psd1`)

Copy `Config\CONTOSO-PROD.example.psd1` to a real file (one per farm, for example
`CONTOSO-PROD-CONTENT.psd1`) and edit the values:

```powershell
@{
    ConfigurationName      = 'PROD'
    ApplicationName        = 'contoso'
    FarmName               = 'CONTENT'
    Domain                 = 'contoso.com'
    CredentialKey          = 'PROD-ADM'

    Binaries               = @{
        ProductUpdate    = $true
        SetupFullPath    = 'D:\SoftwarePackages\SPS\cumulativeupdates'
        SetupFileName    = @('uber-subscription-kb5002651-fullfile-x64-glb.exe')
        ShutdownServices = $true
    }

    MountContentDatabase   = $false
    UpgradeContentDatabase = $true

    SideBySideToken        = @{
        Enable       = $false
        BuildVersion = ''
    }
}
```

### Required keys

| Key | Description |
|---|---|
| `ConfigurationName` | Environment identifier (e.g. `PROD`, `PPRD`, `DEV`). Used in log/result file names. |
| `ApplicationName` | Application/customer code. Used in log/result file names. |
| `FarmName` | Logical farm name. Used in logs and in the ContentDB inventory file name. |
| `Domain` | DNS suffix appended to each farm server short name for CredSSP remoting. |
| `CredentialKey` | Name of the entry in `secrets.psd1` that holds the `InstallAccount`. |

### Optional keys and their defaults

If an optional key is omitted, SPSUpdate applies a safe default:

| Key | Possible values | Default if omitted |
|---|---|---|
| `Binaries.ProductUpdate` | `$true` / `$false` | `$true` |
| `Binaries.ShutdownServices` | `$true` / `$false` | `$true` |
| `UpgradeContentDatabase` | `$true` / `$false` | `$true` |
| `MountContentDatabase` | `$true` / `$false` | `$false` |
| `SideBySideToken.Enable` | `$true` / `$false` | `$false` |
| `SideBySideToken.BuildVersion` | `''` or a build, e.g. `'16.0.17928.20238'` | `''` (skip) |
| `Remoting.AllowFallback` | `$true` / `$false` | `$false` |

`Binaries.SetupFullPath` and `Binaries.SetupFileName` are required as soon as
`ProductUpdate` is `$true`.

> The previous JSON `StoredCredential` key has been renamed to `CredentialKey`, and the
> configuration format moved from JSON to psd1. Runtime/output files (the ContentDB
> inventory and logs) stay JSON by design.

## Secret store (`secrets.psd1`)

The `InstallAccount` credential is stored as a DPAPI-encrypted SecureString. Copy
`Config\secrets.example.psd1` to `Config\secrets.psd1`:

```powershell
@{
    'PROD-ADM' = @{
        Username       = 'CONTOSO\svc_spsupdate'
        PasswordSecure = 'PASTE-ConvertFrom-SecureString-OUTPUT-HERE'
    }
}
```

Each key (e.g. `PROD-ADM`) matches the `CredentialKey` of an environment config. The
recommended way to populate it is to run `-Action Install -InstallAccount (Get-Credential)`
**as the service account**, which writes the entry for you. To generate a value manually,
on the target server signed in as that account:

```powershell
Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
```

> [!IMPORTANT]
> The encrypted value can only be decrypted by the **same user account on the same
> machine**. `secrets.psd1` is gitignored and must never be committed.

## Identity variables

`ConfigurationName`, `ApplicationName` and `FarmName` populate the `Environment`,
`Application` and `FarmName` PowerShell variables used throughout the run and in the
generated file names.

## Binaries settings

Use `ProductUpdate`, `SetupFullPath`, `SetupFileName` and `ShutdownServices` to configure
the binary installation step. `SetupFileName` is an array, so you can list a single uber
package or the STS + WSSLOC (language) pair, installed in order.

### `Binaries.Schedule` (optional)

An optional window restricting **when** the binary install may run:

```powershell
Binaries = @{
    # ...
    Schedule = @{
        Days = @('sat', 'sun')          # optional: allowed days (mon..sun)
        Time = '2:00 AM to 5:00 AM'      # optional: same-day window
    }
}
```

`Days` and `Time` are both optional and independent. Omit `Schedule` (or its keys) to
allow the install at any time. The time window is same-day only (a window crossing
midnight is rejected). Both `Binaries.Schedule` and `Reboot.Schedule` share this shape.

## Reboot (automatic reboot after a CU install)

`Reboot` is an **optional, opt-in** block. When enabled, a server that reports "reboot
required" after the `ProductUpdate` step (installer exit code `17022`) is rebooted
automatically, once, and the live dashboard shows the reboot lifecycle.

```powershell
Reboot = @{
    Enable   = $false                    # opt-in; default $false
    Force    = $false                    # reboot even on exit 0; default $false
    Schedule = @{                        # optional reboot window (same shape as above)
        Days = @('sat', 'sun')
        Time = '3:00 AM to 4:00 AM'
    }
}
```

| Key | Description | Default |
|---|---|---|
| `Enable` | Allow SPSUpdate to reboot a server automatically after a CU install. | `$false` |
| `Force` | Reboot even when the installer did not request one (exit code 0). Leave off to reboot strictly on exit code `17022`. | `$false` |
| `Schedule` | Optional `{ Days, Time }` window restricting when the reboot may happen. Outside the window the dashboard shows the reboot as **pending**. | any time |

**How it works.** The reboot is triggered **only** by the installer exit code `17022`
(never by Windows pending-reboot registry markers, which stay stuck on production farms),
so it happens at most once per patching campaign. Just before rebooting, SPSUpdate marks
the `Reboot` phase as *Running* ("Automatic Reboot launched, check the server in a few
minutes"), writes a Windows Event Log entry (source `Restart-SPSServer`, ID 3010) and
registers a one-shot boot task that, when the server is back, stamps the reboot as *Done*
("Server back online after automatic reboot") and removes itself.

> [!WARNING]
> Reboots are **per-server**. On a farm you remain responsible for not rebooting the sole
> Distributed Cache host or the last available WFE at the same time. Run `ProductUpdate`
> (and its reboot) one server at a time, and keep the farm quorum in mind.

## UpgradeContentDatabase

`UpgradeContentDatabase` runs `Upgrade-SPContentDatabase` in parallel (4 sequences) for
every content database that needs an upgrade.

## MountContentDatabase

`MountContentDatabase` attaches content databases to the target farm before the upgrade
step. It is typically used in farm migration scenarios (for example SharePoint Server
2019 → Subscription Edition) where content databases restored on the target SQL Server
need to be mounted on the new farm. The databases are read from the ContentDatabase
inventory JSON file (`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`,
generated with the `InitContentDB` action).

## SideBySideToken

Use `Enable` to turn on the side-by-side feature and `BuildVersion` to set the build used
by the side-by-side token. Zero downtime patching is a method of patching and upgrade
developed in SharePoint in Microsoft 365. For more details see
[SharePoint Server zero downtime patching steps](https://learn.microsoft.com/en-us/sharepoint/upgrade-and-update/sharepoint-server-2016-zero-downtime-patching-steps).

## StatusStorePath (live dashboard)

`StatusStorePath` is an OPTIONAL UNC share where every farm server writes its patching
progress so the master can assemble the near-real-time HTML dashboard. It must be writable
by the InstallAccount from every server.

```powershell
StatusStorePath = '\\fileserver\spsupdate-status'
```

Leave it empty (or omit it) to fall back to a local `Results\status` folder; in that case
ProductUpdate runs launched on the other servers are not captured centrally. The status
files of one campaign live under `<StatusStorePath>\<App>-<Env>-<Farm>\`, with the
dashboard written there as `_dashboard.html`. See the
[Usage](./Usage) page for the campaign workflow and the `ResetStatus` action.

### Required permissions

Grant the **InstallAccount** (the account that runs the scheduled tasks) **Modify** rights
on the share — both the SMB **share** permission and the **NTFS** permission. The four
upgrade/mount sequence tasks run as that account, so if it cannot write to the share the
upgrade phase never appears on the dashboard (the ProductUpdate and Wizard sections, written
by your interactive/master run under your own account, still show — which can hide the
problem). Run `Test-SPSUpdateReadiness.ps1` to verify both your account and the InstallAccount
can write to the store before patching.

## Dashboard (live HTML report)

The near real-time dashboard is organised as three cards:

- **Binaries Installation** — one row per farm server: status, SharePoint patch status
  (`No Action Required` before patching), installed build and completion time.
- **SharePoint Configuration Wizard** — the same, plus a detail column.
- **Content Databases** — one row per content database: web application, SQL instance, size,
  sequence, upgrade status (`No update pending` when up to date) and processing state.

At the start of the master `Default` run the farm is enumerated with `Get-SPServer` and a
baseline row is pre-filled per server, so the whole farm is visible up front. Because a healthy
farm reports `No Action Required` (servers) and `No update pending` (databases) before a CU is
installed, a server or database that is **not** in that state is highlighted as an informational
**pre-patch inconsistency** banner — a quick health check before patching. The card wording
matches the Central Administration pages exactly.

```powershell
Dashboard = @{
    OutputPath = 'E:\inetpub\spsupdate'   # existing IIS folder; empty = campaign folder
}
```

| Key | Meaning | Default |
|---|---|---|
| `Dashboard.OutputPath` | An **existing** folder (for example an IIS site folder) where the dashboard HTML is written so it can be served over HTTP. SPSUpdate does not create the IIS site — create it once (like the SPSConfigKit pull-server dashboard) and point `OutputPath` at its folder. | `''` (campaign folder) |

The dashboard file name is derived per farm — `<App>-<Env>-<Farm>-dashboard.html` — so several
farms (INT / Preprod / PROD) can share a single IIS folder without colliding. At the start of a
new campaign (`-Action ResetStatus`) the previous dashboard is archived to
`history\<name>_<timestamp>.html` before a fresh one is created.

## Remoting (CredSSP and authentication fallback)

SPSUpdate runs the Configuration Wizard and side-by-side copy on **other** farm servers over
PowerShell remoting. By default it uses **CredSSP**, which is required because the remote
SharePoint cmdlets perform a *second hop* (to the configuration database on SQL, or to a
binaries file share) and CredSSP is the mechanism that delegates the credential for that hop.

The optional `Remoting` block controls what happens when the CredSSP session cannot be opened
(for example on a farm where CredSSP was never configured):

```powershell
Remoting = @{
    AllowFallback = $false   # $true to fall back to Negotiate when CredSSP fails
}
```

| Key | Meaning | Default |
|---|---|---|
| `Remoting.AllowFallback` | When `$true`, fall back to **Negotiate** if the CredSSP session cannot be opened. CredSSP is always tried first. | `$false` |

> **Security / behaviour note.** `Negotiate` (Kerberos with an NTLM fallback) **cannot delegate**
> the credential, so steps that need a second hop may fail unless **Kerberos constrained
> delegation (KCD/RBCD)** is configured for the service account. The fallback is a best-effort
> aid for farms with a broken CredSSP configuration, not a replacement for it — a warning is
> always logged when the fallback is used. Leave it **off** in secure/strict environments.

`Test-SPSUpdateReadiness.ps1` tests this for you: it opens a real short-lived CredSSP session to
each server and reports **PASS** (CredSSP works), **FAIL** (CredSSP failed and
`AllowFallback` is off), or **WARN** (CredSSP failed but the Negotiate fallback works — mind the
double-hop caveat).

## Execution (interactive sequence windows)

By default, the four parallel content-database sequences run as hidden **scheduled tasks**. In
an attended patching campaign you can instead run them in **visible Windows PowerShell windows**
so you can watch each sequence's progress live:

```powershell
Execution = @{
    InteractiveSequences = $true   # visible windows in an attended run; tasks otherwise
}
```

| Key | Meaning | Default |
|---|---|---|
| `Execution.InteractiveSequences` | When `$true` **and** the run is attended (interactive session, not launched by a scheduled task), launch the sequences in visible PowerShell windows instead of scheduled tasks. | `$false` |

Notes:

- The windows run **Windows PowerShell** (`powershell.exe`), because the SharePointServer module
  (Subscription Edition) targets the full .NET Framework and runs on Windows PowerShell 5.1, not
  PowerShell 7.
- They run as the **current user**, who is already a farm administrator when running SPSUpdate
  interactively. The content-database sequences run under that identity, so **no InstallAccount is
  needed** for interactive mode — unlike the scheduled-task path, which must be told which account
  to run as (`-ExecuteAsCredential`). Make sure the signed-in operator has the usual farm-admin and
  content-database rights.
- **Unattended / scheduled runs always use scheduled tasks**, regardless of this setting, because
  interactive windows die when the operator closes the session. Keep runs you launch from a
  scheduled task (or that re-enter with `-Sequence`) on the task path.

## Next Step

For the next steps, go to the [Usage](./Usage) page.
