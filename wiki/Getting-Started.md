# Getting Started

## Prerequisites

- PowerShell 5.0 or later
- CredSSP configured
- Administrative privileges on the SharePoint Server
- StoredCredential configured (if using `Install`)
- SharePoint update binaries copied to a local or accessible path (if using `ProductUpdate`)

## Configure CredSSP

### Option 1: Manually configure CredSSP

You can manually configure CredSSP through the use of some PowerShell cmdlet's (and potentially group policy to configure the allowed delegate computers). Some basic instructions can be found at [https://technet.microsoft.com/en-us/magazine/ff700227.aspx](https://technet.microsoft.com/en-us/magazine/ff700227.aspx).

### Option 2: Configure CredSSP with PowerShell commands

If you prefer automation instead of manual setup, you can configure CredSSP directly with PowerShell commands on the server and client. Example:

```powershell
Enable-WSManCredSSP -Role Server -Force
Enable-WSManCredSSP -Role Client -DelegateComputer '*.contoso.com' -Force
```

In the above example, the delegate computer value can be a wildcard name such as `*.contoso.com`, or you can specify one or more explicit SharePoint servers.

## Installation

1. [Download the latest release](https://github.com/luigilink/SPSUpdate/releases/latest) and unzip to a directory on each SharePoint Server.
2. Prepare your JSON configuration file with the required Cumulative Updates and farm details.
3. Add the script in task scheduler by running the following command:

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD-CONTENT.json' -Action Install -InstallAccount (Get-Credential)
```

1. Install Cumulative Update binaries on each server by running the following command (or install manually):

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD-CONTENT.json' -Action ProductUpdate -InstallAccount (Get-Credential)
```

`ProductUpdate` runs the SharePoint installer directly and does not require any DSC module.

> [!IMPORTANT]
> Configure the StoredCredential parameter in JSON before running the script in installation mode.
> Run the Install mode with the same account than you used the in InstallAccount parameter

## Next Step

For the next steps, go to the [Configuration](./Configuration) page.

## Change log

A full list of changes in each version can be found in the [change log](https://github.com/luigilink/SPSUpdate/blob/main/CHANGELOG.md).
