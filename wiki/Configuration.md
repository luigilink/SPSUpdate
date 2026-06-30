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

## Next Step

For the next steps, go to the [Usage](./Usage) page.
