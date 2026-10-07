# Hosting the dashboard on IIS

The near real-time dashboard is a single, self-contained HTML file. To let the whole team
watch a patching campaign over HTTP — the same way the SPSConfigKit DSC pull-server dashboard
is served — host it on a **fileshare that is also exposed through an IIS binding**.

The recommended target is a **shared UNC path** (`\\server\share\...`): with a UNC
`Dashboard.OutputPath`, every farm server (the master **and** the workers — distributed
`ProductUpdate`, a deferred `ConfirmReboot`) publishes the hosted copy, so the dashboard stays
up to date throughout the campaign. A drive-letter path is treated as *master-local*: only the
master writes it and worker updates never reach the hosted copy.

> SPSUpdate never provisions IIS itself (a patching tool should not create web sites). The
> helper script below is a separate, optional convenience; the steps it automates are also
> documented here so you can do them by hand.

## Option A — helper script (recommended)

`New-SPSDashboardSite.ps1` is a **standalone** script (no dependency on the `SPSUpdate.Common`
module or the rest of the repository): copy just that one file onto the IIS / pull server and
run it from an **elevated** session. It is idempotent and supports `-WhatIf`.

Reusing the existing pull-server site as a sub-application (JC's validated layout):

```powershell
.\New-SPSDashboardSite.ps1 `
    -Path 'C:\inetpub\PSDSCPullServer\SPSUpdate' `
    -ShareName 'SPSUpdate$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' `
    -ParentSite 'PSDSCPullServer' `
    -AppAlias 'SPSUpdate'
```

This creates the folder, shares it as `\\<server>\SPSUpdate$` (Modify for the write accounts),
sets the NTFS permissions, drops a static-file `web.config`, and publishes the folder as a
sub-application of the existing pull-server site. The dashboard is then browsed at
`https://<pull-server>/SPSUpdate/<App>-<Env>-<Farm>-dashboard.html`.

A dedicated site instead of a sub-application:

```powershell
.\New-SPSDashboardSite.ps1 `
    -Path 'E:\inetpub\spsupdate' `
    -ShareName 'spsupdate$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' `
    -SiteName 'SPSUpdateDashboard' -Port 8081
```

| Parameter | Purpose |
|---|---|
| `-Path` | Physical folder that holds the dashboard HTML and is shared/served. |
| `-WriteAccounts` | Account(s) granted **Modify** on the SMB share and NTFS: the account that runs SPSUpdate and/or the InstallAccount. |
| `-ShareName` | SMB share name (e.g. `SPSUpdate$`). Use `-SkipShare` to skip. |
| `-SiteName` / `-Port` | Create a **dedicated** IIS site on this port. |
| `-ParentSite` / `-AppAlias` | Create a **sub-application** under an existing site (e.g. the pull server). |
| `-PoolReadAccount` | Identity granted NTFS **Read** so IIS can serve the files (default `IIS_IUSRS`). |
| `-SkipShare` / `-SkipNtfs` / `-SkipIis` | Run only part of the setup. |
| `-Force` | Overwrite an existing `web.config`. |

The script prints the exact values to put in the config and the browse URL when it finishes.

## Option B — manual setup

Run these on the IIS / pull server from an elevated session (adapt the paths and account):

```powershell
$path = 'C:\inetpub\PSDSCPullServer\SPSUpdate'
New-Item -ItemType Directory -Path $path -Force | Out-Null

# 1) SMB share — Modify for the account that runs SPSUpdate
New-SmbShare -Name 'SPSUpdate$' -Path $path -ChangeAccess 'CONTOSO\svcspsfarm'

# 2) NTFS — Modify for the same account (+ Read for IIS)
$acl  = Get-Acl $path
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'CONTOSO\svcspsfarm','Modify','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($rule)
$read = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'IIS_IUSRS','ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($read)
Set-Acl $path $acl

# 3) Static-file web.config (so .html in a sub-folder of the pull-server site is served)
#    See the web.config content below.

# 4) IIS sub-application under the existing pull-server site
Import-Module WebAdministration
New-WebApplication -Site 'PSDSCPullServer' -Name 'SPSUpdate' -PhysicalPath $path
```

Static-file `web.config` to drop in the folder (needed when the folder is a **sub-folder of an
existing site** whose inherited handlers would otherwise block static `.html`, returning
HTTP 404.17):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <clear />
      <add name="StaticFile" path="*" verb="*" modules="StaticFileModule,DefaultDocumentModule" resourceType="Either" requireAccess="Read" />
    </handlers>
    <staticContent>
      <remove fileExtension=".html" />
      <mimeMap fileExtension=".html" mimeType="text/html" />
    </staticContent>
  </system.webServer>
</configuration>
```

## Permissions summary

| Layer | Right | Who |
|---|---|---|
| SMB share | Modify (Change) | the account that runs SPSUpdate interactively, and/or the InstallAccount |
| NTFS | Modify | same account(s) |
| NTFS | Read | the IIS application-pool identity (`IIS_IUSRS` by default) |
| SMB share + NTFS | Modify | the farm **computer accounts** (e.g. `CONTOSO\Domain Computers`) — **only when the automatic reboot is enabled** (see below) |

The four upgrade/mount sequence tasks run as the **InstallAccount**, so if it cannot write to
the share the upgrade phase never appears on the dashboard. Run `Test-SPSUpdateReadiness.ps1`
to verify both your account and the InstallAccount can write to the store, and that
`Dashboard.OutputPath` exists, is writable, and is a shared UNC path.

### Automatic reboot: grant the farm computer accounts

The one-shot `SPSUpdate-RebootConfirm` boot task (registered when the optional automatic reboot
runs) executes as **`NT AUTHORITY\SYSTEM`** so it needs no stored credential. On the network, a
`SYSTEM` task authenticates as the **computer account** (`DOMAIN\SERVER$`), so each rebooting
server must be able to write `Reboot=Done` to the UNC status store as its machine account.

Grant the farm computer accounts **Modify** on both the SMB share and NTFS. The simplest option is
to add `Domain Computers` (or the specific server `$` accounts) to `-WriteAccounts` when provisioning
the share:

```powershell
.\New-SPSDashboardSite.ps1 -Path 'C:\inetpub\PSDSCPullServer\SPSUpdate' -ShareName 'SPSUpdate$' `
    -WriteAccounts 'CONTOSO\svcspsfarm','CONTOSO\Domain Computers' `
    -ParentSite 'PSDSCPullServer' -AppAlias 'SPSUpdate'
```

If the share does not grant the machine accounts, the CU still installs and the server still
reboots, but `-Action ConfirmReboot` cannot persist the completion: it logs a clear warning and
retries on the next boot, and the dashboard stays on the `Reboot` running state until the grant is
added. This grant is only needed when the automatic reboot (`Reboot.Enable = $true`) is used.

## Point SPSUpdate at it

In your environment config (`Config\<App>-<Env>-<Farm>.psd1`):

```powershell
StatusStorePath = '\\PULL\SPSUpdate$'
Dashboard       = @{ OutputPath = '\\PULL\SPSUpdate$' }
```

The dashboard file name is derived per farm (`<App>-<Env>-<Farm>-dashboard.html`), so several
farms (INT / Preprod / PROD) can share one folder without colliding. Run `-Action ResetStatus`
to publish the initial dashboard, then open the browse URL.

## Next Step

- [⚙️ Configuration](Configuration)
- [📖 Usage](Usage)
