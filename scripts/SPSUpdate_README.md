# SPSUpdate Installation Guide

This document provides instructions for installing and configuring the **SPSUpdate** PowerShell script in environments without internet access. It is intended for SharePoint On-Premises administrators who need to install cumulative updates in your SharePoint environment.

## 📦 Prerequisites

- SharePoint Server (2016 or later)
- Administrator privileges on the server
- PowerShell 5.1 or later
- Valid credentials for task scheduler setup
- StoredCredential configured (if using Install)
- CredSSP configured

## 📁 Files Required

Ensure the following files are available locally:

- `SPSUpdate.ps1` (main script)
- Any dependencies or modules used by the script (if applicable)

## 🛠 Installation Steps

### 1. Copy Files to Server

Place `SPSUpdate.ps1` and any dependencies or modules in a local folder on the SharePoint server, e.g., `E:\SCRIPT\`.

### 2. Prepare your JSON configuration

To customize the script for your environment, you need to prepare a JSON configuration file. Below is a sample structure for the file:

```json
{
  "$schema": "http://json-schema.org/schema#",
  "contentVersion": "1.0.0.0",
  "ConfigurationName": "PROD",
  "ApplicationName": "contoso",
  "FarmName": "CONTENT",
  "Domain": "contoso.com",
  "StoredCredential": "PROD-ADM",
  "Binaries": {
    "ProductUpdate": true,
    "SetupFullPath": "D:\\SoftwarePackages\\SPS\\cumulativeupdates",
    "SetupFileName": ["uber-subscription-kb5002651-fullfile-x64-glb.exe"],
    "ShutdownServices": false
  },
  "UpgradeContentDatabase": true,
  "MountContentDatabase": false,
  "SideBySideToken": {
    "Enable": true,
    "BuildVersion": "16.0.17928.20238"
  }
}
```

#### Configuration, Application and FarmName

`ConfigurationName` is used to populate the content of `Environment` PowerShell Variable.
`ApplicationName` is used to populate the content of `Application` PowerShell Variable.
`FarmName` is used to populate the content of `FarmName` PowerShell Variable.

#### Credential Manager

`StoredCredential` is refered to the target of your credential that you used during the installation processus.

#### Binaries settings

Use `ProductUpdate`, `SetupFullPath`, `SetupFileName` and `ShutdownServices` parameters to configure your binaries settings in your environment

#### UpgradeContentDatabase

The `UpgradeContentDatabase` parameter can be used to run upgrade-SPContentDatabase in parallel.

The authorized values are : `true`, and `false`.

#### MountContentDatabase

The `MountContentDatabase` parameter can be used to mount content databases on the target
farm before the upgrade. This is typically used during a farm migration scenario (for
example SharePoint Server 2019 → Subscription Edition) where databases coming from the
source farm have been restored on the SQL Server of the target farm and now need to be
attached to it.

When set to `true`, the script loads the ContentDatabase inventory JSON file
(`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`) and runs
`Mount-SPContentDatabase` for each database that is not already attached. Mounts are
performed sequentially on the master server to avoid concurrent writes to the
configuration database. The inventory JSON file is normally generated on the source farm
with the `InitContentDB` action and then copied next to the script on the target farm.

The authorized values are : `true`, and `false`.

#### SideBySideToken

Use `Enable` to enable sidebysidetoken feature.
Use `BuildVersion` to set build version used in sidebysitetoken feature.

### 3. Run Script with Install Action parameter

Open PowerShell as Administrator and execute:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'E\SCRIPTS\Config\contoso-PROD-CONTENT.json'
```

This will:

- Validate credentials
- Add one scheduled task to run if The `UpgradeContentDatabase` parameter is set to `false`
- Add five scheduled tasks to run if The `UpgradeContentDatabase` parameter is set to `true`
- Save all content database in `contoso-PROD-CONTENT-ContentDBs.json` file

### 4. Run Script with Install ProductUpdate parameter

Place `SPSUpdate.ps1`, any dependencies or modules and the configuration file in a local folder on each other SharePoint server, e.g., `E:\SCRIPT\`.

On each SharePoint Server, open PowerShell as Administrator and execute:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action ProductUpdate -ConfigFile 'E\SCRIPTS\Config\contoso-PROD-CONTENT.json'
```

This will:

- Unblock cumulative update files if it is blocked
- Running Start-SPSProductUpdate function

> Note: Starting with version 3.2.0 the ProductUpdate action no longer aborts when the
> Windows reboot markers (Component Based Servicing, PendingFileRenameOperations, etc.)
> are still present, because those markers were observed to persist on healthy production
> farms even after multiple reboots and were blocking legitimate updates.

### 5. Run Script with InitContentDB Action parameter (source farm)

The `InitContentDB` action (re)generates the ContentDatabase inventory JSON file
(`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`) located in the
`Config` folder next to the script. It is typically used on the source farm before a
farm upgrade (for example SharePoint Server 2019 → Subscription Edition) so that the
generated inventory can be copied to the target farm to drive the
`MountContentDatabase` step.

On the source SharePoint Server, open PowerShell as Administrator and execute:

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action InitContentDB -ConfigFile 'E\SCRIPTS\Config\contoso-PROD-CONTENT.json'
```

This will:

- Run `Initialize-SPSContentDbJsonFile` against the local farm
- Overwrite any existing inventory file so it always reflects the current state of the farm
- Produce a JSON file split into 4 balanced groups (`SPContentDatabase1` to `SPContentDatabase4`) that can be consumed by the Mount and parallel Upgrade flows on the target farm

## 🔄 Uninstalling

```powershell
E:\SCRIPT\SPSUpdate.ps1 -Action Uninstall
```

## 📚 Additional Notes

- The script automatically creates Logs folder and per-run log file (sequence-aware naming) and starts a transcript (Start-Transcript) for full output capture.
- It verifies script is running with Administrator rights before proceeding.
- It detects installed SharePoint version (Get-SPSInstalledProductVersion) and loads the appropriate SharePoint snap-in or module.
- The Full-run mode creates 4 sequence tasks (SPSUpdate-Sequence1..4) and starts them in parallel (with random short sleeps to avoid OWSTimer conflicts)
- When `MountContentDatabase` is `true`, the master server attaches the content databases listed in the inventory JSON file (skipping databases that are already mounted) before launching the parallel upgrade tasks.
- The script runs Start-SPSConfigExe locally and Start-SPSConfigExeRemote for other servers; configures SideBySide token (Set-SPSSideBySideToken) and copies side-by-side files remotely if enabled.

## 📄 License

MIT License

## 👤 Authors

- Jean-Cyril Drouhin (luigilink)

For more details, refer to the embedded comments in `SPSUpdate.ps1`.
