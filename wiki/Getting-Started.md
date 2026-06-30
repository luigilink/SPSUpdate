# Getting Started

## Prerequisites

- PowerShell 5.1 or later (no DSC module required)
- CredSSP configured (used for remoting to the other farm servers)
- Administrative privileges on each SharePoint Server
- A service account (`InstallAccount`) whose credential is stored in `Config\secrets.psd1`
- SharePoint update binaries copied to a local or accessible path (if using `ProductUpdate`)
- (Optional, for the live dashboard) a UNC share for the status store with **Modify** rights for the InstallAccount — see [Configuration](./Configuration#statusstorepath-live-dashboard)

## Configure CredSSP

### Option 1: Manually configure CredSSP

You can manually configure CredSSP through a few PowerShell cmdlets (and potentially group policy to configure the allowed delegate computers). Basic guidance is available in the Microsoft documentation.

### Option 2: Configure CredSSP with PowerShell commands

If you prefer automation instead of manual setup, configure CredSSP directly with PowerShell on the server and client. Example:

```powershell
Enable-WSManCredSSP -Role Server -Force
Enable-WSManCredSSP -Role Client -DelegateComputer '*.contoso.com' -Force
```

In the above example the delegate computer value can be a wildcard such as `*.contoso.com`, or one or more explicit SharePoint servers.

## Installation

1. [Download the latest release](https://github.com/luigilink/SPSUpdate/releases/latest) and unzip to a directory on each SharePoint Server. The archive extracts straight to `SPSUpdate.ps1`, `Config\` and `Modules\` (no `src\` wrapper).
2. Copy `Config\CONTOSO-PROD.example.psd1` to a real config (for example `CONTOSO-PROD-CONTENT.psd1`) and edit the values for your farm. See [Configuration](./Configuration).
3. Register the scheduled tasks by running the following command **as the service account** that will run them:

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action Install -InstallAccount (Get-Credential)
```

4. Install the cumulative update binaries on each server (or install them manually):

```powershell
.\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1' -Action ProductUpdate
```

`ProductUpdate` runs the SharePoint installer directly, locally, and does not require the `InstallAccount` parameter.

> [!IMPORTANT]
> Run `-Action Install` **as the same account** you pass to `-InstallAccount`. The credential is stored as a DPAPI-encrypted SecureString in `Config\secrets.psd1`, which can only be decrypted by that account on that machine.

## The credential store (DPAPI)

SPSUpdate no longer depends on the Windows Credential Manager module. The `InstallAccount`
credential is encrypted with `ConvertFrom-SecureString` (DPAPI) and stored under the
`CredentialKey` entry of `Config\secrets.psd1`. `-Action Install` writes it for you;
`-Action Uninstall` removes it. See [Configuration](./Configuration) for the file format.

## Next Step

For the next steps, go to the [Configuration](./Configuration) page.

## Change log

A full list of changes in each version can be found in the [change log](https://github.com/luigilink/SPSUpdate/blob/main/CHANGELOG.md).
