# SPSUpdate Installation Guide

This document provides instructions for installing and configuring the **SPSUpdate**
PowerShell script in environments **without internet access**. It is intended for
SharePoint On-Premises administrators who need to install cumulative updates in their
SharePoint environment.

> This guide ships inside the release package so it is available offline on the server.
> For the full online documentation, see the [SPSUpdate Wiki](https://github.com/luigilink/SPSUpdate/wiki).

## 📦 Prerequisites

- SharePoint Server 2016, 2019 or Subscription Edition
- Administrator privileges on the server
- PowerShell 5.1 or later (no DSC module required)
- A service account (`InstallAccount`) for the scheduled tasks and CredSSP remoting
- CredSSP configured (used to reach the other farm servers)

## 📁 Files Required

The release package extracts directly to the following layout — keep them together:

- `SPSUpdate.ps1` (main script)
- `Modules\SPSUpdate.Common\` (the helper module — **required**)
- `Config\` (your environment `*.psd1` config and the DPAPI `secrets.psd1`)

## 🛠 Installation Steps

### 1. Copy files to the server

Place `SPSUpdate.ps1`, the `Modules\` folder and the `Config\` folder in a local folder
on the SharePoint server, e.g. `E:\SCRIPT\`.

### 2. Prepare your environment configuration (psd1)

Copy `Config\CONTOSO-PROD.example.psd1` to a real file (one per farm, e.g.
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

#### ConfigurationName, ApplicationName and FarmName

`ConfigurationName`, `ApplicationName` and `FarmName` populate the `Environment`,
`Application` and `FarmName` PowerShell variables and are used in the log/result and
ContentDB inventory file names. All three are required.

#### CredentialKey and the secret store (DPAPI)

`CredentialKey` is the name of the entry in `Config\secrets.psd1` that holds the
`InstallAccount`. SPSUpdate no longer uses the Windows Credential Manager: the credential
is stored as a DPAPI-encrypted SecureString. Running `-Action Install` as the service
account writes it for you (see step 3). To create it manually, on the server signed in as
that account:

```powershell
Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
```

Paste the result into `Config\secrets.psd1` (copy `secrets.example.psd1`). The value can
only be decrypted by the same account on the same machine. `secrets.psd1` must never be
shared or committed.

#### Binaries settings

Use `ProductUpdate`, `SetupFullPath`, `SetupFileName` and `ShutdownServices` to configure
the binary installation step. `SetupFileName` is an array (single uber package, or the
STS + WSSLOC language pair installed in order).

#### UpgradeContentDatabase and MountContentDatabase

`UpgradeContentDatabase` runs `Upgrade-SPContentDatabase` in parallel (4 sequences) for
databases that need it. `MountContentDatabase` attaches databases listed in the ContentDB
inventory (typically for a 2019 → Subscription Edition migration). Both accept `$true` or
`$false`.

#### SideBySideToken

Use `Enable` to turn on side-by-side patching and `BuildVersion` to set the token build
(leave empty to skip).

### 3. Run the script with the Install action

Open PowerShell **as the service account** (Run as a different user) and as Administrator,
then execute:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

This will:

- Validate the credential and store it in `Config\secrets.psd1` (DPAPI)
- Add one scheduled task (`SPSUpdate-FullScript`) when `UpgradeContentDatabase` and
  `MountContentDatabase` are both `$false`
- Add five scheduled tasks (`SPSUpdate-FullScript` + `SPSUpdate-Sequence1..4`) when either
  is `$true`

> Run `-Action Install` as the **same account** you pass to `-InstallAccount`, so the
> DPAPI secret can be decrypted by the scheduled tasks at run time.

### 4. (Optional) Generate the ContentDB inventory — read-only

On the source farm, you can build the content-database inventory without changing anything:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

This writes `<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json` (plus a
timestamped snapshot) under `Config\` and installs/upgrades nothing.

### 5. Install the cumulative update binaries on each server

Copy the same folder to each SharePoint server. On each server, open PowerShell as
Administrator and execute:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

This will:

- Unblock the cumulative update file(s) if blocked
- Run `Start-SPSProductUpdate` for each setup file (optionally stopping/restoring services
  when `ShutdownServices` is `$true`)

`ProductUpdate` runs the SharePoint installer locally and does **not** require the
`InstallAccount` parameter.

## ▶️ Running the upgrade (full mode)

After the binaries are installed on every server, run the default mode once on the master
server. It mounts/upgrades the content databases in parallel (4 sequences), then runs the
post-setup Configuration Wizard (PSConfig) locally and on every other server over CredSSP,
and configures the side-by-side token when enabled:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

## 📡 Near real-time dashboard (optional)

Set `StatusStorePath` in the config to a UNC share writable by the InstallAccount from
every server to get a live HTML dashboard of the patching campaign:

1. `SPSUpdate.ps1 -ConfigFile '<farm>.psd1' -Action ResetStatus` (clears the campaign).
2. Open `<StatusStorePath>\<App>-<Env>-<Farm>\_dashboard.html` in a browser (auto-refresh).
3. Run `-Action ProductUpdate` on each server, then the default master run.

If `StatusStorePath` is empty, the dashboard falls back to the local `Results\status`
folder (ProductUpdate on other servers is then not captured centrally).

> IMPORTANT: grant the InstallAccount (the scheduled-task service account) **Modify** on the
> share (SMB share + NTFS). The upgrade/mount sequence tasks run as that account; without
> write access the upgrade phase will not appear on the dashboard. Run
> `Test-SPSUpdateReadiness.ps1` to verify it (it probes write access as both your account and
> the InstallAccount).

## ✅ Pre-flight readiness check (optional)

```powershell
E:\SCRIPT\Test-SPSUpdateReadiness.ps1 -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

Read-only validation of the module, config, DPAPI secret, elevation, status store write
access and CredSSP reachability. Exits non-zero on any failure.

## 🔄 Uninstalling

To remove the scheduled tasks and the stored secret:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action Uninstall -ConfigFile 'E:\SCRIPT\Config\CONTOSO-PROD-CONTENT.psd1'
```

## 📚 Additional notes

- Creates a `Logs` folder and a per-run transcript (sequence/action-aware naming).
- Verifies the script runs with Administrator rights before proceeding.
- Detects the installed SharePoint version (`Get-SPSInstalledProductVersion`) and loads the
  appropriate SharePoint snap-in (2016/2019) or the `SharePointServer` module (SE).
- Full mode creates four sequence tasks (`SPSUpdate-Sequence1..4`) and starts them in
  parallel (with short random sleeps to avoid OWSTimer conflicts).
- Remote operations (PSConfig, side-by-side) use CredSSP and fail with a clear error if the
  session cannot be opened (they never silently fall back to the local server).
- Lifecycle and error events are written to the dedicated `SPSUpdate` Windows Event Log.

## 📄 License

MIT License

## 👤 Authors

- Jean-Cyril Drouhin (luigilink)

For more details, refer to the embedded comments in `SPSUpdate.ps1` or the
[SPSUpdate Wiki](https://github.com/luigilink/SPSUpdate/wiki).
