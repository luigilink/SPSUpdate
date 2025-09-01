# Usage Guide for `SPSUpdate.ps1`

## Overview

`SPSUpdate.ps1` is a PowerShell script tool designed to install cumulative updates and run SPConfig.exe in your SharePoint environment.

## Prerequisites

- PowerShell 5.1 or later.
- Necessary permissions to access the SharePoint Farm.
- Ensure the script is placed in a directory accessible by the user.

## Parameters

| Parameter         | Description                                                                                                                                                                                                            |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-ConfigFile`     | Specifies the path to the configuration file.                                                                                                                                                                          |
| `-Sequence`       | Specifies the Sequence for parallel upgrade Content DB.                                                                                                                                                                |
| `-Action`         | (Optional) Use the Action parameter equal to Install to add the script in taskscheduler, InstallAccount parameter need to be set. Use the Action parameter equal to Uninstall to remove the script from taskscheduler. |
| `-InstallAccount` | (Optional) Need parameter InstallAccount whent you use the Action parameter equal to Install.                                                                                                                          |
| `-Uninstall`      | Remove the SPSUpdate script from task scheduler                                                                                                                                                                        |

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

## Logging

The script logs the status of each task, including success or failure, and saves it to the specified log file or the default location.

## Error Handling

- Ensure the provided credentials have access to the SharePoint Farm.

## Notes

- Test the script in a non-production environment before deploying it widely.

## Support

For issues or questions, please contact the script maintainer or refer to the project documentation.
