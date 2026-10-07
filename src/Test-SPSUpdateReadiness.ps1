<#
    .SYNOPSIS
    Pre-flight readiness check for SPSUpdate.

    .DESCRIPTION
    Validates, before running SPSUpdate.ps1, that the environment is ready:
    the SPSUpdate.Common module imports, the environment configuration parses
    and exposes the required keys, the service credential exists in secrets.psd1
    and decrypts under the current account (DPAPI), the session is elevated, the
    status store (UNC share, v4.2.0+) is writable, and each farm server is
    reachable for CredSSP remoting. When the optional Dashboard.OutputPath is set,
    it also checks that folder exists and is writable, and warns when it is a
    master-local (drive-letter) path rather than a shared UNC path.

    Read-only: it never changes configuration, credentials or the farm. The only
    side effect is a temporary probe file written and immediately deleted in the
    status store to confirm it is writable.

    .PARAMETER ConfigFile
    Path to the environment configuration .psd1 file (same one passed to
    SPSUpdate.ps1). secrets.psd1 is looked up in the same folder.

    .PARAMETER SkipNetwork
    Skip the local WinRM prerequisite checks and the per-server WinRM/CredSSP reachability
    probes (useful off-server).

    .PARAMETER SkipSharePoint
    Skip enumerating the farm servers via Get-SPServer.

    .EXAMPLE
    .\Test-SPSUpdateReadiness.ps1 -ConfigFile 'Config\CONTOSO-PROD-CONTENT.psd1'

    .NOTES
    FileName:   Test-SPSUpdateReadiness.ps1
    Author:     luigilink (Jean-Cyril DROUHIN)
    Project:    https://github.com/luigilink/SPSUpdate
#>

#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'This is an interactive, operator-facing readiness tool whose purpose is colored console output.')]
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $ConfigFile,

    [Parameter()]
    [switch]
    $SkipNetwork,

    [Parameter()]
    [switch]
    $SkipSharePoint,

    [Parameter()]
    [System.Int32]
    $TimeoutSeconds = 5
)

$script:results = New-Object System.Collections.Generic.List[object]

function Add-CheckResult {
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Section,
        [Parameter(Mandatory = $true)] [System.String] $Name,
        [Parameter(Mandatory = $true)] [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')] [System.String] $Status,
        [Parameter()] [System.String] $Detail = ''
    )

    $script:results.Add([PSCustomObject]@{ Section = $Section; Name = $Name; Status = $Status; Detail = $Detail })

    switch ($Status) {
        'PASS' { $color = 'Green'; $glyph = '[ OK ]' }
        'FAIL' { $color = 'Red'; $glyph = '[FAIL]' }
        'WARN' { $color = 'Yellow'; $glyph = '[WARN]' }
        'SKIP' { $color = 'DarkGray'; $glyph = '[SKIP]' }
    }
    $line = '{0}  {1}' -f $glyph, $Name
    if (-not [string]::IsNullOrEmpty($Detail)) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Write-Section {
    param ([System.String] $Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SPSUpdate - Readiness Check' -ForegroundColor Cyan
Write-Host "  Computer : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# 1. Module
Write-Section -Title 'Module'
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSUpdate.Common\SPSUpdate.Common.psd1'
if (Test-Path -Path $modulePath) {
    try {
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $version = (Get-Module -Name SPSUpdate.Common).Version
        Add-CheckResult -Section 'Module' -Name 'SPSUpdate.Common import' -Status 'PASS' -Detail "v$version"
    }
    catch {
        Add-CheckResult -Section 'Module' -Name 'SPSUpdate.Common import' -Status 'FAIL' -Detail $_.Exception.Message
    }
}
else {
    Add-CheckResult -Section 'Module' -Name 'SPSUpdate.Common import' -Status 'FAIL' -Detail "Module not found at $modulePath"
}

# 2. Configuration
Write-Section -Title 'Configuration'
$cfg = $null
if (-not (Test-Path -Path $ConfigFile)) {
    Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'FAIL' -Detail "Not found: $ConfigFile"
}
else {
    try {
        $cfg = Import-PowerShellDataFile -Path $ConfigFile -ErrorAction Stop
        Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'PASS' -Detail $ConfigFile
    }
    catch {
        Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'FAIL' -Detail "Parse error: $($_.Exception.Message)"
    }
}

if ($null -ne $cfg) {
    foreach ($key in @('ConfigurationName', 'ApplicationName', 'Domain', 'FarmName', 'CredentialKey')) {
        if ($cfg.Contains($key) -and -not [string]::IsNullOrWhiteSpace([string]$cfg[$key])) {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'PASS'
        }
        else {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'FAIL' -Detail 'Missing or empty'
        }
    }

    if ($cfg.Contains('Binaries') -and $cfg.Binaries) {
        if ([string]::IsNullOrEmpty($cfg.Binaries.SetupFullPath)) {
            Add-CheckResult -Section 'Config' -Name 'Binaries.SetupFullPath' -Status 'WARN' -Detail 'Empty (required when ProductUpdate is enabled)'
        }
        else {
            Add-CheckResult -Section 'Config' -Name 'Binaries.SetupFullPath' -Status 'PASS' -Detail $cfg.Binaries.SetupFullPath
        }
    }
    else {
        Add-CheckResult -Section 'Config' -Name 'Binaries block' -Status 'WARN' -Detail 'Missing (ProductUpdate defaults will apply)'
    }
}

# 3. Secrets (DPAPI)
Write-Section -Title 'Secrets'
if ($null -ne $cfg -and $cfg.Contains('CredentialKey') -and $cfg.CredentialKey) {
    $configFolder = Split-Path -Path $ConfigFile -Parent
    if ([string]::IsNullOrEmpty($configFolder)) { $configFolder = '.' }
    $secretsPath = Join-Path -Path $configFolder -ChildPath 'secrets.psd1'
    if (-not (Test-Path -Path $secretsPath)) {
        Add-CheckResult -Section 'Secrets' -Name 'secrets.psd1' -Status 'FAIL' -Detail "Not found at $secretsPath. Run SPSUpdate.ps1 -Action Install as the service account."
    }
    else {
        if ($null -eq (Get-Module -Name SPSUpdate.Common)) {
            Add-CheckResult -Section 'Secrets' -Name 'Get-SPSSecret' -Status 'SKIP' -Detail 'Module not loaded; cannot validate the secret'
        }
        else {
            try {
                $cred = Get-SPSSecret -CredentialKey $cfg.CredentialKey -ConfigPath $configFolder -ErrorAction Stop
                if ($null -ne $cred -and $cred.GetNetworkCredential().Password.Length -gt 0) {
                    Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'PASS' -Detail "DPAPI decrypt OK (user: $($cred.UserName))"
                }
                else {
                    Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'FAIL' -Detail 'Not found in secrets.psd1'
                }
            }
            catch {
                Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'FAIL' -Detail "Decrypt failed (wrong account/machine?): $($_.Exception.Message)"
            }
        }
    }
}
else {
    Add-CheckResult -Section 'Secrets' -Name 'CredentialKey' -Status 'SKIP' -Detail 'No CredentialKey in config'
}

# 4. Privileges
Write-Section -Title 'Privileges'
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if ($isAdmin) {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'PASS'
}
else {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'FAIL' -Detail 'Run elevated (needed for the Event Log and SharePoint cmdlets)'
}

# 5. Status store (UNC share for the live dashboard)
Write-Section -Title 'Status store'
if ($null -ne $cfg -and $cfg.Contains('StatusStorePath') -and -not [string]::IsNullOrWhiteSpace([string]$cfg.StatusStorePath)) {
    $storePath = [string]$cfg.StatusStorePath
    if (-not (Test-Path -Path $storePath)) {
        Add-CheckResult -Section 'StatusStore' -Name 'Status store path' -Status 'FAIL' -Detail "Not reachable: $storePath"
    }
    else {
        $probe = Join-Path -Path $storePath -ChildPath (".spsupdate-readiness-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        try {
            Set-Content -Path $probe -Value 'readiness' -ErrorAction Stop
            Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue
            Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (current user)' -Status 'PASS' -Detail $storePath
        }
        catch {
            Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (current user)' -Status 'FAIL' -Detail "Cannot write to $storePath : $($_.Exception.Message)"
        }

        # CRITICAL: the four upgrade/mount sequence tasks run as the InstallAccount (the
        # scheduled-task service account), not as the interactive user. If that account
        # cannot write to the share, the sequences silently fail to publish their status
        # and the dashboard never shows the upgrade phase. Probe write access AS the
        # InstallAccount by launching a short process under its credential and checking
        # whether the file actually lands on the share.
        $svcCred = $null
        if ($null -ne $cfg -and $cfg.Contains('CredentialKey') -and $cfg.CredentialKey -and (Get-Command -Name Get-SPSSecret -ErrorAction SilentlyContinue)) {
            $configFolder2 = Split-Path -Path $ConfigFile -Parent
            if ([string]::IsNullOrEmpty($configFolder2)) { $configFolder2 = '.' }
            try { $svcCred = Get-SPSSecret -CredentialKey $cfg.CredentialKey -ConfigPath $configFolder2 -ErrorAction Stop } catch { $svcCred = $null }
        }

        if ($null -eq $svcCred) {
            Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (service account)' -Status 'WARN' -Detail 'Could not load the InstallAccount to test; ensure it has Modify on the share (the sequence tasks run as that account)'
        }
        else {
            $svcProbe = Join-Path -Path $storePath -ChildPath (".spsupdate-readiness-svc-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
            $svcCmd = "Set-Content -LiteralPath '$svcProbe' -Value 'readiness-svc' -ErrorAction Stop"
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($svcCmd))
            try {
                $proc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                    -Credential $svcCred `
                    -WorkingDirectory "$env:SystemRoot" `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
                    -Wait -PassThru -ErrorAction Stop
                $null = $proc
                Start-Sleep -Milliseconds 500
                if (Test-Path -Path $svcProbe) {
                    Remove-Item -Path $svcProbe -Force -ErrorAction SilentlyContinue
                    Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (service account)' -Status 'PASS' -Detail "InstallAccount '$($svcCred.UserName)' can write to the share"
                }
                else {
                    Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (service account)' -Status 'FAIL' -Detail "InstallAccount '$($svcCred.UserName)' cannot write to $storePath. Grant it Modify on the share + NTFS; otherwise the upgrade sequences will not appear on the dashboard."
                }
            }
            catch {
                Add-CheckResult -Section 'StatusStore' -Name 'Status store writable (service account)' -Status 'WARN' -Detail "Could not launch a probe as '$($svcCred.UserName)' ($($_.Exception.Message)). Verify it has 'Log on as a batch job' and Modify on the share."
            }
        }
    }
}
else {
    Add-CheckResult -Section 'StatusStore' -Name 'StatusStorePath' -Status 'WARN' -Detail 'Not set; the live dashboard will use the local Results\status folder and will not capture ProductUpdate on other servers'
}

# 5b. Dashboard hosting (optional Dashboard.OutputPath)
Write-Section -Title 'Dashboard'
$dashOutputPath = $null
if ($null -ne $cfg -and $cfg.Contains('Dashboard') -and $null -ne $cfg.Dashboard) {
    try { $dashOutputPath = [string]$cfg.Dashboard.OutputPath } catch { $dashOutputPath = $null }
}
if ([string]::IsNullOrWhiteSpace($dashOutputPath)) {
    Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath' -Status 'SKIP' -Detail 'Not set; the dashboard is written into the status store campaign folder'
}
else {
    # A shared UNC path (\\server\share\...) lets every farm server publish the hosted copy; a
    # drive-letter path is master-local, so worker runs cannot update it (see the IIS hosting wiki).
    $isUnc = $dashOutputPath.StartsWith('\\') -or $dashOutputPath.StartsWith('//')
    if ($isUnc) {
        Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath is shared (UNC)' -Status 'PASS' -Detail $dashOutputPath
    }
    else {
        Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath is shared (UNC)' -Status 'WARN' -Detail "'$dashOutputPath' is a local path, writable only by the master; worker runs (distributed ProductUpdate, ConfirmReboot) cannot update the hosted dashboard. Prefer a shared UNC path served by IIS (see the Hosting the dashboard on IIS wiki)."
    }
    if (-not (Test-Path -Path $dashOutputPath)) {
        Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath exists' -Status 'FAIL' -Detail "Folder not found: $dashOutputPath. SPSUpdate does not create it; provision it first (see New-SPSDashboardSite.ps1)."
    }
    else {
        $dashProbe = Join-Path -Path $dashOutputPath -ChildPath (".spsupdate-readiness-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        try {
            Set-Content -Path $dashProbe -Value 'readiness' -ErrorAction Stop
            Remove-Item -Path $dashProbe -Force -ErrorAction SilentlyContinue
            Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (current user)' -Status 'PASS' -Detail $dashOutputPath
        }
        catch {
            Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (current user)' -Status 'FAIL' -Detail "Cannot write to $dashOutputPath : $($_.Exception.Message)"
        }

        # The sequence tasks render as the InstallAccount, so probe the dashboard folder as that
        # account too. (ConfirmReboot runs as SYSTEM - that path is checked separately below.)
        $storeForCompare = ''
        if ($null -ne $cfg -and $cfg.Contains('StatusStorePath')) { $storeForCompare = ([string]$cfg.StatusStorePath).TrimEnd('\', '/') }
        $dashForCompare = $dashOutputPath.TrimEnd('\', '/')
        if ($dashForCompare -ieq $storeForCompare) {
            Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'SKIP' -Detail 'Same folder as the status store (already verified above)'
        }
        else {
            $dashSvcCred = $null
            if ($null -ne $cfg -and $cfg.Contains('CredentialKey') -and $cfg.CredentialKey -and (Get-Command -Name Get-SPSSecret -ErrorAction SilentlyContinue)) {
                $dashConfigFolder = Split-Path -Path $ConfigFile -Parent
                if ([string]::IsNullOrEmpty($dashConfigFolder)) { $dashConfigFolder = '.' }
                try { $dashSvcCred = Get-SPSSecret -CredentialKey $cfg.CredentialKey -ConfigPath $dashConfigFolder -ErrorAction Stop } catch { $dashSvcCred = $null }
            }
            if (-not (Test-Path -Path $dashOutputPath)) {
                Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'SKIP' -Detail 'Folder not found; see the failure above'
            }
            elseif ($null -eq $dashSvcCred) {
                Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'WARN' -Detail 'Could not load the InstallAccount to test; ensure it has Modify on the dashboard folder (the scheduled sequences render as that account)'
            }
            else {
                $dashSvcProbe = Join-Path -Path $dashOutputPath -ChildPath (".spsupdate-readiness-svc-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
                $dashSvcCmd = "Set-Content -LiteralPath '$dashSvcProbe' -Value 'readiness-svc' -ErrorAction Stop"
                $dashEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($dashSvcCmd))
                try {
                    $dashProc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                        -Credential $dashSvcCred `
                        -WorkingDirectory "$env:SystemRoot" `
                        -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $dashEncoded) `
                        -Wait -PassThru -ErrorAction Stop
                    $null = $dashProc
                    Start-Sleep -Milliseconds 500
                    if (Test-Path -Path $dashSvcProbe) {
                        Remove-Item -Path $dashSvcProbe -Force -ErrorAction SilentlyContinue
                        Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'PASS' -Detail "InstallAccount '$($dashSvcCred.UserName)' can write to the dashboard folder"
                    }
                    else {
                        Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'FAIL' -Detail "InstallAccount '$($dashSvcCred.UserName)' cannot write to $dashOutputPath. Grant it Modify; otherwise worker renders (sequences) will not update the hosted dashboard."
                    }
                }
                catch {
                    Add-CheckResult -Section 'Dashboard' -Name 'Dashboard.OutputPath writable (service account)' -Status 'WARN' -Detail "Could not launch a probe as '$($dashSvcCred.UserName)' ($($_.Exception.Message)). Verify it has 'Log on as a batch job' and Modify on the dashboard folder."
                }
            }
        }
    }
}

# 5c. Reboot status store (machine accounts) - independent of Dashboard.OutputPath.
# Reboot enabled + UNC store: the SYSTEM boot task writes as the computer account, which we
# cannot probe here - surface an explicit WARN about the required machine-account grant.
$rebootEnabled = $false
try { $rebootEnabled = [bool]$cfg.Reboot.Enable } catch { $rebootEnabled = $false }
if ($rebootEnabled) {
    $storeForReboot = ''
    try { $storeForReboot = [string]$cfg.StatusStorePath } catch { $storeForReboot = '' }
    if ([string]::IsNullOrWhiteSpace($storeForReboot) -and $null -ne $dashOutputPath) { $storeForReboot = $dashOutputPath }
    if ($storeForReboot -like '\\*') {
        Add-CheckResult -Section 'Dashboard' -Name 'Reboot status store (machine accounts)' -Status 'WARN' -Detail "Automatic reboot is enabled: the boot ConfirmReboot task runs as SYSTEM and writes to '$storeForReboot' as the computer account. Grant the farm machine accounts (e.g. 'Domain Computers') Modify on the share + NTFS (add them to New-SPSDashboardSite.ps1 -WriteAccounts). This cannot be auto-verified here."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($storeForReboot)) {
        Add-CheckResult -Section 'Dashboard' -Name 'Reboot status store (machine accounts)' -Status 'WARN' -Detail 'Automatic reboot is enabled but the status store is a local path; the boot ConfirmReboot task (SYSTEM) on other servers cannot reach it. Use a shared UNC status store and grant the farm machine accounts Modify.'
    }
}

# 6. Network / CredSSP reachability
Write-Section -Title 'Network'
# Local WinRM / PS remoting prerequisite, checked before the per-server probes so a missing
# local setup surfaces as one clear cause rather than per-server "Unreachable" warnings.
if (-not $SkipNetwork) {
    $winrmService = Get-Service -Name 'WinRM' -ErrorAction SilentlyContinue
    $winrmRunning = $null -ne $winrmService -and $winrmService.Status -eq 'Running'
    if ($null -eq $winrmService) {
        Add-CheckResult -Section 'Network' -Name 'WinRM service' -Status 'FAIL' -Detail 'WinRM service not found; run Enable-PSRemoting -Force'
    }
    elseif (-not $winrmRunning) {
        Add-CheckResult -Section 'Network' -Name 'WinRM service' -Status 'FAIL' -Detail "WinRM service is $($winrmService.Status); run Enable-PSRemoting -Force (or Start-Service WinRM)"
    }
    else {
        Add-CheckResult -Section 'Network' -Name 'WinRM service' -Status 'PASS' -Detail 'Running'
    }

    if (-not $winrmRunning) {
        # Skip the localhost probe when the service is down: it would only add a redundant WARN
        # that obscures the primary WinRM service FAIL above.
        Add-CheckResult -Section 'Network' -Name 'Local PS remoting (Test-WSMan)' -Status 'SKIP' -Detail 'Not tested; WinRM service is not running'
    }
    else {
        try {
            Test-WSMan -ComputerName localhost -ErrorAction Stop | Out-Null
            Add-CheckResult -Section 'Network' -Name 'Local PS remoting (Test-WSMan)' -Status 'PASS' -Detail 'WinRM responds on localhost'
        }
        catch {
            Add-CheckResult -Section 'Network' -Name 'Local PS remoting (Test-WSMan)' -Status 'WARN' -Detail "Test-WSMan localhost failed: $($_.Exception.Message); run Enable-PSRemoting -Force"
        }
    }
}
if ($SkipNetwork) {
    Add-CheckResult -Section 'Network' -Name 'Farm reachability' -Status 'SKIP' -Detail '-SkipNetwork specified'
}
elseif ($null -ne $cfg -and $cfg.Contains('Domain') -and $cfg.Domain) {
    $targets = New-Object System.Collections.Generic.List[string]

    if (-not $SkipSharePoint -and (Get-Command -Name Get-SPServer -ErrorAction SilentlyContinue)) {
        try {
            $farmServers = @(Get-SPServer | Where-Object { $_.Role -ne 'Invalid' } | Select-Object -ExpandProperty Name)
            foreach ($s in $farmServers) {
                $fqdn = if ($s -like '*.*') { $s } else { "$s.$($cfg.Domain)" }
                if ($targets -notcontains $fqdn) { $targets.Add($fqdn) }
            }
            Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'PASS' -Detail "$($farmServers.Count) server(s) via Get-SPServer"
        }
        catch {
            Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'SKIP' -Detail "Get-SPServer unavailable: $($_.Exception.Message)"
        }
    }
    else {
        Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'SKIP' -Detail 'SharePoint not loaded; cannot enumerate servers'
    }

    # Remoting.AllowFallback is read raw here; default to the secure $false and reject a
    # non-Boolean value (which Get-SPSUpdateConfiguration also rejects at run time).
    $allowFallback = $false
    if ($null -ne $cfg -and $cfg.Contains('Remoting') -and $cfg.Remoting -and $cfg.Remoting.Contains('AllowFallback')) {
        if ($cfg.Remoting.AllowFallback -is [bool]) {
            $allowFallback = $cfg.Remoting.AllowFallback
        }
        else {
            Add-CheckResult -Section 'Network' -Name 'Remoting.AllowFallback' -Status 'FAIL' -Detail "Must be a Boolean (`$true/`$false); the run will reject '$($cfg.Remoting.AllowFallback)'"
        }
    }

    foreach ($target in ($targets | Sort-Object -Unique)) {
        # 6a. WinRM transport reachability, using the interactive identity (informational only).
        $cim = $null
        try {
            $opt = New-CimSessionOption -Protocol Wsman
            $cim = New-CimSession -ComputerName $target -OperationTimeoutSec $TimeoutSeconds -SessionOption $opt -ErrorAction Stop
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'PASS' -Detail 'WinRM reachable'
        }
        catch {
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'WARN' -Detail "Unreachable within ${TimeoutSeconds}s: $($_.Exception.Message)"
        }
        finally {
            if ($cim) { Remove-CimSession -CimSession $cim -ErrorAction SilentlyContinue }
        }

        # 6b. Real CredSSP test with the service credential. This is independent of the transport
        # probe above (which uses the interactive identity), so always attempt it when $cred is
        # available - a CredSSP session can succeed even if the interactive WinRM probe warned.
        if ($null -eq $cred) {
            Add-CheckResult -Section 'Network' -Name "CredSSP to $target" -Status 'SKIP' -Detail 'No decrypted credential available (see Secrets); cannot test CredSSP'
            continue
        }

        $sessionOpt = New-PSSessionOption -OpenTimeout ($TimeoutSeconds * 1000)
        $credsspSession = $null
        try {
            $credsspSession = New-PSSession -ComputerName $target -Credential $cred -Authentication CredSSP `
                -SessionOption $sessionOpt -ErrorAction Stop
            Add-CheckResult -Section 'Network' -Name "CredSSP to $target" -Status 'PASS' -Detail "CredSSP session opened as $($cred.UserName)"
        }
        catch {
            $credsspError = $_.Exception.Message
            if (-not $allowFallback) {
                Add-CheckResult -Section 'Network' -Name "CredSSP to $target" -Status 'FAIL' -Detail "CredSSP failed and Remoting.AllowFallback is off: $credsspError"
            }
            else {
                # Fallback enabled: confirm Negotiate works so the operator knows the run can proceed.
                $negSession = $null
                try {
                    $negSession = New-PSSession -ComputerName $target -Credential $cred -Authentication Negotiate `
                        -SessionOption $sessionOpt -ErrorAction Stop
                    Add-CheckResult -Section 'Network' -Name "CredSSP to $target" -Status 'WARN' -Detail "CredSSP failed; Negotiate fallback works, but double-hop steps (SQL/file share) may fail without Kerberos delegation: $credsspError"
                }
                catch {
                    Add-CheckResult -Section 'Network' -Name "CredSSP to $target" -Status 'FAIL' -Detail "Both CredSSP and Negotiate failed. CredSSP: $credsspError | Negotiate: $($_.Exception.Message)"
                }
                finally {
                    if ($negSession) { Remove-PSSession -Session $negSession -ErrorAction SilentlyContinue }
                }
            }
        }
        finally {
            if ($credsspSession) { Remove-PSSession -Session $credsspSession -ErrorAction SilentlyContinue }
        }
    }
}
else {
    Add-CheckResult -Section 'Network' -Name 'Farm reachability' -Status 'SKIP' -Detail 'No Domain to build server FQDNs'
}

# Summary
$fail = @($script:results | Where-Object Status -eq 'FAIL').Count
$warn = @($script:results | Where-Object Status -eq 'WARN').Count
$pass = @($script:results | Where-Object Status -eq 'PASS').Count
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host (' Summary : {0} passed, {1} warning(s), {2} failure(s)' -f $pass, $warn, $fail) -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 } else { exit 0 }
