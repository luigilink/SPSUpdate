# Getting Started

## Prerequisites

- PowerShell 5.0 or later
- CredSSP configured
- SharePointDsc Installed (if using `ProductUpdate`)
- Administrative privileges on the SharePoint Server
- StoredCredential configured (if using `Install`)

## Configure CredSSP

### Option 1: Manually configure CredSSP

You can manually configure CredSSP through the use of some PowerShell cmdlet's (and potentially group policy to configure the allowed delegate computers). Some basic instructions can be found at [https://technet.microsoft.com/en-us/magazine/ff700227.aspx](https://technet.microsoft.com/en-us/magazine/ff700227.aspx).

### Option 2: Configure CredSSP through a DSC resource

It is possible to use a DSC resource to configure your CredSSP settings on a server, and include this in all of your SharePoint server configurations. This is done through the use of the [xCredSSP](https://github.com/PowerShell/xCredSSP) resource. The below example shows how this can be used.

```powershell
xCredSSP CredSSPServer { Ensure = "Present"; Role = "Server" }
xCredSSP CredSSPClient { Ensure = "Present"; Role = "Client"; DelegateComputers = $CredSSPDelegates }
```

In the above example, `$CredSSPDelegates` can be a wildcard name (such as "\*.contoso.com" to allow all servers in the contoso.com domain), or a list of specific servers (such as "server1", "server 2" to allow only specific servers).

## Installation

1. [Download the latest release](https://github.com/luigilink/SPSUpdate/releases/latest) and unzip to a directory on each SharePoint Server.
2. Prepare your JSON configuration file with the required Cumulative Updates and farm details.
3. Add the script in task scheduler by running the following command:

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD-CONTENT.json' -Action Install -InstallAccount (Get-Credential)
```

4. Install Cumulative Update binaries on each server by running the following command (or install manually):

```powershell
.\SPSUpdate.ps1 -ConfigFile 'contoso-PROD-CONTENT.json' -Action ProductUpdate -InstallAccount (Get-Credential)
```

> [!IMPORTANT]
> Configure the StoredCredential parameter in JSON before running the script in installation mode.
> Run the Install mode with the same account than you used the in InstallAccount parameter

## Next Step

For the next steps, go to the [Configuration](./Configuration) page.

## Change log

A full list of changes in each version can be found in the [change log](https://github.com/luigilink/SPSUpdate/blob/main/CHANGELOG.md).
