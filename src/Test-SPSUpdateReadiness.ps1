<#
    .SYNOPSIS
    Pre-flight readiness check for SPSUpdate.

    .DESCRIPTION
    Validates, before running SPSUpdate.ps1, that the environment is ready:
    the SPSUpdate.Common module imports, the environment configuration parses
    and exposes the required keys, the service credential exists in secrets.psd1
    and decrypts under the current account (DPAPI), the session is elevated, the
    status store (UNC share, v4.2.0+) is writable, and each farm server is
    reachable for CredSSP remoting.

    Read-only: it never changes configuration, credentials or the farm. The only
    side effect is a temporary probe file written and immediately deleted in the
    status store to confirm it is writable.

    .PARAMETER ConfigFile
    Path to the environment configuration .psd1 file (same one passed to
    SPSUpdate.ps1). secrets.psd1 is looked up in the same folder.

    .PARAMETER SkipNetwork
    Skip the per-server WinRM/CredSSP reachability probe (useful off-server).

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
            Add-CheckResult -Section 'StatusStore' -Name 'Status store writable' -Status 'PASS' -Detail $storePath
        }
        catch {
            Add-CheckResult -Section 'StatusStore' -Name 'Status store writable' -Status 'FAIL' -Detail "Cannot write to $storePath : $($_.Exception.Message)"
        }
    }
}
else {
    Add-CheckResult -Section 'StatusStore' -Name 'StatusStorePath' -Status 'WARN' -Detail 'Not set; the live dashboard will use the local Results\status folder and will not capture ProductUpdate on other servers'
}

# 6. Network / CredSSP reachability
Write-Section -Title 'Network'
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

    foreach ($target in ($targets | Sort-Object -Unique)) {
        $cim = $null
        try {
            $opt = New-CimSessionOption -Protocol Wsman
            $cim = New-CimSession -ComputerName $target -OperationTimeoutSec $TimeoutSeconds -SessionOption $opt -ErrorAction Stop
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'PASS' -Detail 'Confirm CredSSP is enabled for the full run'
        }
        catch {
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'WARN' -Detail "Unreachable within ${TimeoutSeconds}s: $($_.Exception.Message)"
        }
        finally {
            if ($cim) { Remove-CimSession -CimSession $cim -ErrorAction SilentlyContinue }
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
