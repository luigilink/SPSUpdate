# Configuration

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

## Configuration, Application and FarmName

`ConfigurationName` is used to populate the content of `Environment` PowerShell Variable.
`ApplicationName` is used to populate the content of `Application` PowerShell Variable.
`FarmName` is used to populate the content of `FarmName` PowerShell Variable.

## Credential Manager

`StoredCredential` is refered to the target of your credential that you used during the installation processus.

## Binaries settings

Use `ProductUpdate`, `SetupFullPath`, `SetupFileName` and `ShutdownServices` parameters to configure your binaries settings in your environment

## UpgradeContentDatabase

The `UpgradeContentDatabase` parameter can be used to run upgrade-SPContentDatabase in parallel.

The authorized values are : `true`, and `false`.

## MountContentDatabase

The `MountContentDatabase` parameter can be used to attach content databases to the
target farm before the upgrade step. It is typically used in farm migration scenarios
(for example SharePoint Server 2019 → Subscription Edition) where content databases
restored from the source farm on the target SQL Server need to be mounted on the new
farm.

When set to `true`, the master server iterates through the ContentDatabase inventory
JSON file (`<ApplicationName>-<ConfigurationName>-<FarmName>-ContentDBs.json`, normally
generated on the source farm with the `InitContentDB` action) and runs
`Mount-SPContentDatabase` for every database that is not already attached. Mounts are
performed sequentially on the master server to avoid concurrent writes to the
configuration database.

The authorized values are : `true`, and `false`.

## SideBySideToken

Use `Enable` to enable sidebysidetoken feature.
Use `BuildVersion` to set build version used in sidebysitetoken feature.

Zero downtime patching is a method of patching and upgrade developed in SharePoint in Microsoft 365. For more details see [SharePoint Server zero downtime patching steps](https://learn.microsoft.com/en-us/sharepoint/upgrade-and-update/sharepoint-server-2016-zero-downtime-patching-steps)

## Next Step

For the next steps, go to the [Usage](./Usage) page.
