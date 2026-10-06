<#
    .SYNOPSIS
    Prepare an IIS-served fileshare to host the SPSUpdate near real-time dashboard.

    .DESCRIPTION
    One-time, idempotent helper that provisions the hosting target for the SPSUpdate
    dashboard the same way the SPSConfigKit DSC pull-server dashboard is served: a folder
    shared over SMB (so every farm server can write its *-dashboard.html there) and exposed
    through an IIS binding (so operators browse it over HTTP).

    It performs, in order (each step is idempotent and honors -WhatIf):
      1. creates the target folder,
      2. creates or updates an SMB share granting Modify to the write accounts
         (the interactive operator account and/or the InstallAccount that runs SPSUpdate),
      3. sets NTFS Modify for those accounts and Read for the IIS application-pool identity,
      4. writes a static-file web.config so an .html served from a sub-folder of an existing
         site is not blocked by inherited handlers (avoids HTTP 404.17),
      5. creates either a dedicated IIS site (-SiteName/-Port) or a sub-application under an
         existing site (-ParentSite/-AppAlias), pointing at the folder.

    It then prints the value to set in the SPSUpdate config (Dashboard.OutputPath) and the
    browse URL.

    This script is deliberately STANDALONE: it has no dependency on the SPSUpdate.Common
    module or the rest of the repository, so you can copy just this single .ps1 onto the
    IIS / pull server and run it there. SPSUpdate.ps1 itself never provisions IIS; this is a
    separate, optional convenience. Windows-only (uses the SmbShare and WebAdministration
    modules); the SMB/IIS steps are skipped with a clear warning when those modules are absent.

    .PARAMETER Path
    Absolute path of the folder that will hold the dashboard HTML and be shared/served.
    Example: 'C:\inetpub\PSDSCPullServer\SPSUpdate'.

    .PARAMETER WriteAccounts
    One or more accounts granted Modify on both the SMB share and NTFS (the account that runs
    SPSUpdate interactively and/or the InstallAccount). Example: 'CONTOSO\svcspsfarm'.
    Required unless both -SkipShare and -SkipNtfs are specified.

    .PARAMETER ShareName
    Name of the SMB share to create/update (e.g. 'SPSUpdate$'). Required unless -SkipShare.

    .PARAMETER SiteName
    Create a dedicated IIS web site with this name bound to -Port, rooted at -Path. Mutually
    exclusive with -ParentSite/-AppAlias.

    .PARAMETER Port
    TCP port for the dedicated IIS site (used with -SiteName). Defaults to 8081.

    .PARAMETER ParentSite
    Name of an EXISTING IIS site under which to create a sub-application (e.g. the pull-server
    site). Used with -AppAlias. Mutually exclusive with -SiteName.

    .PARAMETER AppAlias
    Virtual path (alias) of the sub-application created under -ParentSite (e.g. 'SPSUpdate',
    browsed as https://<parent>/SPSUpdate/...). Used with -ParentSite.

    .PARAMETER PoolReadAccount
    Identity granted NTFS Read so IIS can serve the files. Defaults to the local 'IIS_IUSRS'
    group, which covers application-pool identities.

    .PARAMETER SkipShare
    Do not create/update the SMB share (folder + NTFS + IIS only).

    .PARAMETER SkipNtfs
    Do not change NTFS permissions.

    .PARAMETER SkipIis
    Do not create the IIS site/sub-application (folder + share only).

    .PARAMETER Force
    Overwrite the static-file web.config if it already exists.

    .EXAMPLE
    .\New-SPSDashboardSite.ps1 -Path 'C:\inetpub\PSDSCPullServer\SPSUpdate' -ShareName 'SPSUpdate$' -WriteAccounts 'CONTOSO\svcspsfarm' -ParentSite 'PSDSCPullServer' -AppAlias 'SPSUpdate'

    Shares C:\...\SPSUpdate as \\<server>\SPSUpdate$ and exposes it as a sub-application of the
    existing pull-server site, browsed at https://<pull-server>/SPSUpdate/<App>-<Env>-<Farm>-dashboard.html.

    .EXAMPLE
    .\New-SPSDashboardSite.ps1 -Path 'E:\inetpub\spsupdate' -ShareName 'spsupdate$' -WriteAccounts 'CONTOSO\svcspsfarm','CONTOSO\jc-adm' -SiteName 'SPSUpdateDashboard' -Port 8081 -WhatIf

    Dry run that would create a dedicated IIS site on port 8081.

    .NOTES
    FileName:   New-SPSDashboardSite.ps1
    Author:     luigilink (Jean-Cyril DROUHIN)
    Project:    https://github.com/luigilink/SPSUpdate
#>

#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'This is an interactive, operator-facing provisioning tool whose purpose is colored console output.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $Path,

    [Parameter()]
    [System.String[]]
    $WriteAccounts,

    [Parameter()]
    [System.String]
    $ShareName,

    [Parameter()]
    [System.String]
    $SiteName,

    [Parameter()]
    [System.Int32]
    $Port = 8081,

    [Parameter()]
    [System.String]
    $ParentSite,

    [Parameter()]
    [System.String]
    $AppAlias,

    [Parameter()]
    [System.String]
    $PoolReadAccount = 'IIS_IUSRS',

    [Parameter()]
    [switch]
    $SkipShare,

    [Parameter()]
    [switch]
    $SkipNtfs,

    [Parameter()]
    [switch]
    $SkipIis,

    [Parameter()]
    [switch]
    $Force
)

# --- Self-contained colored output helpers --------------------------------------------
function Write-Step {
    param ([System.String] $Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}
function Write-Ok { param([System.String] $Message) Write-Host "[ OK ]  $Message" -ForegroundColor Green }
function Write-Info { param([System.String] $Message) Write-Host "[INFO]  $Message" -ForegroundColor Gray }
function Write-Warn { param([System.String] $Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Fail { param([System.String] $Message) Write-Host "[FAIL]  $Message" -ForegroundColor Red }

# Build a browse base URL (proto://host[:port]) from an IIS binding object, honoring the real
# protocol, host header and port (an existing binding may be HTTPS and/or carry a host header, so
# a hard-coded http://<computer>:<port> would be wrong).
function Get-BrowseBaseFromBinding {
    param($Binding)
    $proto = if ($Binding.protocol) { "$($Binding.protocol)" } else { 'http' }
    $parts = "$($Binding.bindingInformation)" -split ':'
    $port = if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { $parts[1] } elseif ($proto -eq 'https') { '443' } else { '80' }
    $hostName = if ($parts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { $parts[2] } else { $env:COMPUTERNAME }
    $isDefaultPort = ($proto -eq 'http' -and $port -eq '80') -or ($proto -eq 'https' -and $port -eq '443')
    if ($isDefaultPort) { return "$proto`://$hostName" }
    return "$proto`://$hostName`:$port"
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SPSUpdate - Dashboard IIS hosting setup' -ForegroundColor Cyan
Write-Host "  Computer : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# --- Parameter validation -------------------------------------------------------------
$iisBySite = -not [string]::IsNullOrWhiteSpace($SiteName)
$iisBySubApp = -not [string]::IsNullOrWhiteSpace($ParentSite) -or -not [string]::IsNullOrWhiteSpace($AppAlias)

if ($iisBySite -and $iisBySubApp) {
    throw 'Specify either -SiteName (a dedicated site) OR -ParentSite/-AppAlias (a sub-application), not both.'
}
if ($iisBySubApp -and ([string]::IsNullOrWhiteSpace($ParentSite) -or [string]::IsNullOrWhiteSpace($AppAlias))) {
    throw 'A sub-application requires BOTH -ParentSite and -AppAlias.'
}
if (-not $SkipIis -and -not $iisBySite -and -not $iisBySubApp) {
    throw 'Provide an IIS target: -SiteName (+ -Port) for a dedicated site, or -ParentSite + -AppAlias for a sub-application. Use -SkipIis to configure the folder/share only.'
}
if (-not $SkipShare -and [string]::IsNullOrWhiteSpace($ShareName)) {
    throw 'Provide -ShareName for the SMB share, or use -SkipShare.'
}
if ((-not $SkipShare -or -not $SkipNtfs) -and (-not $WriteAccounts -or $WriteAccounts.Count -eq 0)) {
    throw 'Provide -WriteAccounts (the account(s) that run SPSUpdate and must write the dashboard), or skip both the share and NTFS steps.'
}

# --- Elevation check ------------------------------------------------------------------
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run from an elevated (Run as administrator) session.'
}

# --- 1. Folder ------------------------------------------------------------------------
Write-Step -Title 'Folder'
if (Test-Path -Path $Path -PathType Container) {
    Write-Ok "Folder already exists: $Path"
}
else {
    if ($PSCmdlet.ShouldProcess($Path, 'Create folder')) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Ok "Created folder: $Path"
    }
    else {
        Write-Info "[WhatIf] Would create folder: $Path"
    }
}

# --- 2. SMB share ---------------------------------------------------------------------
# Track whether the share is actually usable so the final summary only advertises the UNC
# path when it was really created/verified (never on a module-absent or name-collision skip).
$shareReady = $false
$sharePlanned = $false
if ($SkipShare) {
    Write-Step -Title 'SMB share (skipped)'
    Write-Info 'Skipped (-SkipShare).'
}
else {
    Write-Step -Title 'SMB share'
    if (-not (Get-Command -Name Get-SmbShare -ErrorAction SilentlyContinue)) {
        Write-Warn 'The SmbShare module is not available on this machine; skipping the share step. Create the share manually.'
    }
    else {
        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
        if ($null -eq $existingShare) {
            if ($PSCmdlet.ShouldProcess("\\$env:COMPUTERNAME\$ShareName", 'Create SMB share')) {
                New-SmbShare -Name $ShareName -Path $Path -ChangeAccess $WriteAccounts -FullAccess 'BUILTIN\Administrators' -ErrorAction Stop | Out-Null
                Write-Ok "Created share \\$env:COMPUTERNAME\$ShareName (Modify: $($WriteAccounts -join ', '))"
                $shareReady = $true
            }
            else {
                Write-Info "[WhatIf] Would create share \\$env:COMPUTERNAME\$ShareName with Modify for $($WriteAccounts -join ', ')"
                $sharePlanned = $true
            }
        }
        else {
            if ("$($existingShare.Path)" -ne "$Path") {
                # The share name is already taken by an UNRELATED folder: do NOT grant our write
                # accounts Change access to someone else's share. Warn and skip the permission
                # reconciliation entirely; the operator must resolve the collision manually.
                Write-Warn "Share '$ShareName' already exists but points to '$($existingShare.Path)' (expected '$Path'). Left unchanged and permissions NOT modified - resolve the name collision manually (use a different -ShareName)."
            }
            else {
                Write-Ok "Share \\$env:COMPUTERNAME\$ShareName already exists."
                $shareReady = $true
                foreach ($acct in $WriteAccounts) {
                    if ($PSCmdlet.ShouldProcess("$ShareName => $acct", 'Grant SMB Change access')) {
                        Grant-SmbShareAccess -Name $ShareName -AccountName $acct -AccessRight Change -Force -ErrorAction Stop | Out-Null
                        Write-Ok "Granted SMB Modify to $acct on $ShareName"
                    }
                    else {
                        Write-Info "[WhatIf] Would grant SMB Modify to $acct on $ShareName"
                    }
                }
            }
        }
    }
}

# --- 3. NTFS permissions --------------------------------------------------------------
if ($SkipNtfs) {
    Write-Step -Title 'NTFS permissions (skipped)'
    Write-Info 'Skipped (-SkipNtfs).'
}
else {
    Write-Step -Title 'NTFS permissions'
    if (-not (Test-Path -Path $Path)) {
        Write-Info "[WhatIf] Folder not created yet; would set NTFS permissions on $Path"
    }
    elseif ($PSCmdlet.ShouldProcess($Path, 'Set NTFS permissions')) {
        $acl = Get-Acl -Path $Path
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        foreach ($acct in $WriteAccounts) {
            try {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($acct, 'Modify', $inherit, $prop, $allow)
                $acl.AddAccessRule($rule)
                Write-Ok "NTFS Modify queued for $acct"
            }
            catch {
                Write-Warn "Could not resolve account '$acct' for NTFS Modify: $($_.Exception.Message)"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($PoolReadAccount)) {
            try {
                $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule($PoolReadAccount, 'ReadAndExecute', $inherit, $prop, $allow)
                $acl.AddAccessRule($readRule)
                Write-Ok "NTFS Read queued for $PoolReadAccount (IIS)"
            }
            catch {
                Write-Warn "Could not resolve IIS read account '$PoolReadAccount': $($_.Exception.Message)"
            }
        }
        Set-Acl -Path $Path -AclObject $acl
        Write-Ok "Applied NTFS permissions on $Path"
    }
    else {
        Write-Info "[WhatIf] Would set NTFS Modify ($($WriteAccounts -join ', ')) and Read ($PoolReadAccount) on $Path"
    }
}

# --- 4. Static-file web.config --------------------------------------------------------
Write-Step -Title 'Static-file web.config'
$webConfigPath = Join-Path -Path $Path -ChildPath 'web.config'
$webConfigBody = @'
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
'@
if ((Test-Path -Path $webConfigPath) -and -not $Force) {
    Write-Ok "web.config already present (use -Force to overwrite): $webConfigPath"
}
elseif ($PSCmdlet.ShouldProcess($webConfigPath, 'Write static-file web.config')) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($webConfigPath, ($webConfigBody -replace "`r`n", "`n").Replace("`n", "`r`n"), $enc)
    Write-Ok "Wrote static-file web.config: $webConfigPath"
}
else {
    Write-Info "[WhatIf] Would write static-file web.config: $webConfigPath"
}

# --- 5. IIS site / sub-application ----------------------------------------------------
$browseBase = $null
if ($SkipIis) {
    Write-Step -Title 'IIS (skipped)'
    Write-Info 'Skipped (-SkipIis).'
}
else {
    Write-Step -Title 'IIS'
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        Write-Warn 'The WebAdministration module is not available (is this the IIS/pull server?); skipping the IIS step. Create the site/sub-application manually.'
    }
    else {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $pathNorm = "$Path".TrimEnd('\', '/')
        if ($iisBySite) {
            $existingSite = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
            if ($null -ne $existingSite) {
                # A pre-existing site with this name may serve a different folder or port; only
                # accept it (and advertise the URL) when it actually points at $Path. Build the URL
                # from the real matching binding (protocol/host/port), not a hard-coded http://.
                $sitePhys = "$($existingSite.physicalPath)".TrimEnd('\', '/')
                $matchBinding = $existingSite.bindings.Collection | Where-Object { "$($_.bindingInformation)" -match "[:]$Port[:]" } | Select-Object -First 1
                if ($sitePhys -ine $pathNorm) {
                    Write-Warn "IIS site '$SiteName' already exists but serves '$($existingSite.physicalPath)' (expected '$Path'). Left unchanged - resolve the collision (use a different -SiteName) or point it at '$Path' manually."
                }
                elseif ($null -eq $matchBinding) {
                    Write-Warn "IIS site '$SiteName' serves '$Path' but has no binding on port $Port. Review its bindings manually."
                    $firstBinding = $existingSite.bindings.Collection | Select-Object -First 1
                    if ($null -ne $firstBinding) { $browseBase = Get-BrowseBaseFromBinding -Binding $firstBinding }
                }
                else {
                    Write-Ok "IIS site '$SiteName' already serves '$Path' on port $Port."
                    $browseBase = Get-BrowseBaseFromBinding -Binding $matchBinding
                }
            }
            elseif ($PSCmdlet.ShouldProcess("$SiteName (port $Port)", 'Create IIS site')) {
                New-Website -Name $SiteName -PhysicalPath $Path -Port $Port -Force | Out-Null
                Write-Ok "Created IIS site '$SiteName' on port $Port."
                $browseBase = "http://$($env:COMPUTERNAME):$Port"
            }
            else {
                Write-Info "[WhatIf] Would create IIS site '$SiteName' on port $Port."
                $browseBase = "http://$($env:COMPUTERNAME):$Port"
            }
        }
        else {
            $parent = Get-Website -Name $ParentSite -ErrorAction SilentlyContinue
            if ($null -eq $parent) {
                Write-Fail "Parent IIS site '$ParentSite' does not exist. Create it first, or use -SiteName for a dedicated site."
            }
            else {
                # Build the browse base from the parent site's real binding (protocol/host/port),
                # not from the site NAME, so the printed URL actually resolves.
                $binding = $parent.bindings.Collection | Select-Object -First 1
                $parentBase = if ($null -ne $binding) { Get-BrowseBaseFromBinding -Binding $binding } else { "https://$env:COMPUTERNAME" }
                $existingApp = Get-WebApplication -Site $ParentSite -Name $AppAlias -ErrorAction SilentlyContinue
                if ($null -ne $existingApp) {
                    # A pre-existing sub-application with this alias may point elsewhere; only accept
                    # it (and advertise the URL) when its physical path is $Path.
                    $appPhys = "$($existingApp.PhysicalPath)".TrimEnd('\', '/')
                    if ($appPhys -ine $pathNorm) {
                        Write-Warn "Sub-application '/$AppAlias' already exists under '$ParentSite' but points to '$($existingApp.PhysicalPath)' (expected '$Path'). Left unchanged - resolve the collision (use a different -AppAlias) or re-point it at '$Path' manually."
                    }
                    else {
                        Write-Ok "Sub-application '/$AppAlias' already serves '$Path' under '$ParentSite'."
                        $browseBase = "$parentBase/$AppAlias"
                    }
                }
                elseif ($PSCmdlet.ShouldProcess("$ParentSite/$AppAlias", 'Create IIS sub-application')) {
                    New-WebApplication -Site $ParentSite -Name $AppAlias -PhysicalPath $Path -Force | Out-Null
                    Write-Ok "Created sub-application '/$AppAlias' under '$ParentSite'."
                    $browseBase = "$parentBase/$AppAlias"
                }
                else {
                    Write-Info "[WhatIf] Would create sub-application '/$AppAlias' under '$ParentSite'."
                    $browseBase = "$parentBase/$AppAlias"
                }
            }
        }
    }
}

# --- Summary --------------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Done. Next steps' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
if ($shareReady -or $sharePlanned) {
    $uncPath = "\\$env:COMPUTERNAME\$ShareName"
    Write-Host ''
    if ($sharePlanned) {
        Write-Host '[WhatIf] Once the share is created, set this in your SPSUpdate config (shared UNC so every farm server publishes to it):' -ForegroundColor Gray
    }
    else {
        Write-Host 'Set this in your SPSUpdate config (shared UNC so every farm server publishes to it):' -ForegroundColor Gray
    }
    Write-Host "    StatusStorePath = '$uncPath'" -ForegroundColor White
    Write-Host "    Dashboard = @{ OutputPath = '$uncPath' }" -ForegroundColor White
}
elseif (-not $SkipShare) {
    Write-Host ''
    Write-Warn 'The SMB share was not created/verified (module missing or name collision); the config UNC path above is not shown. Create the share manually, then set StatusStorePath / Dashboard.OutputPath to it.'
}
if (-not [string]::IsNullOrWhiteSpace($browseBase)) {
    Write-Host ''
    Write-Host 'Browse the dashboard (file name is derived per farm as <App>-<Env>-<Farm>-dashboard.html):' -ForegroundColor Gray
    Write-Host "    $browseBase/<App>-<Env>-<Farm>-dashboard.html" -ForegroundColor White
}
Write-Host ''
