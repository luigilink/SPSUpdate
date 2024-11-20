# Usage

## Parameters

| Parameter         | Description                                               |
| ----------------- | --------------------------------------------------------- |
| `-ConfigFile`     | Specifies the path to the configuration file.             |
| `-Sequence`       | Specifies the Sequence for parallel upgrade Content DB.   |
| `-Install`        | Add the SPSUpdate script in task scheduler                |
| `-InstallAccount` | Specifies the service account who runs the scheduled task |
| `-Uninstall`      | Remove the SPSUpdate script from task scheduler           |

### Basic Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json'
```

### Sequence Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Sequence 1
```

### Installation Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Install -InstallAccount (Get-Credential)
```

### Uninstallation Usage Example

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD.json' -Uninstall
```
