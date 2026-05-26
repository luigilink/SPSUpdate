# Usage Guide for `SPSUpdate.ps1`

## Overview

`SPSUpdate.ps1` is a PowerShell script tool designed to install cumulative updates and run SPConfig.exe in your SharePoint environment.

## Prerequisites

- PowerShell 5.1 or later.
- Necessary permissions to access the SharePoint Farm.
- Ensure the script is placed in a directory accessible by the user.
- Copy the script and cumulative update files on each SharePoint Server.

## Parameters

| Parameter         | Description                                                                                                                                                                                                                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ConfigFile`     | Specifies the path to the configuration file.                                                                                                                                                                                                                                                     |
| `Sequence`       | (Optional) Specifies the Sequence for parallel upgrade Content DB.                                                                                                                                                                                                                                |
| `Action`         | (Optional) Accepts `Install`, `Uninstall`, `Default`, `ProductUpdate` or `InitContentDB`. `Install`/`Uninstall` manage the scheduled tasks (requires `InstallAccount` for `Install`). `ProductUpdate` installs the binaries locally. `InitContentDB` (re)generates the ContentDatabase inventory JSON file. |
| `InstallAccount` | (Optional) Need parameter InstallAccount when you use the Action parameter equal to Install.                                                                                                                                                                                                      |

## Examples

### Example 1: Default Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json'
```

### Example 2: Sequence Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Sequence 1
```

### Example 3: Installation Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Action Install -InstallAccount (Get-Credential)
```

### Example 4: Uninstallation Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Action Uninstall
```

### Example 5: ProductUpdate Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Action ProductUpdate
```

### Example 6: InitContentDB Usage Example (source farm)

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Action InitContentDB
```

This action (re)generates the ContentDatabase inventory JSON file
(`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`) for the local farm.
It is typically used on the source farm before a farm upgrade (for example
SharePoint Server 2019 → Subscription Edition) so that the inventory can be copied to
the target farm and consumed by the `MountContentDatabase` flow.

## Logging

The script logs the status of each task, including success or failure, and saves it to the specified log file or the default location.

## Error Handling

- Ensure the account running the script has administrator rights and access to the SharePoint Farm.

## Notes

- Test the script in a non-production environment before deploying it widely.

## Support

For issues or questions, please contact the script maintainer or refer to the project documentation.
