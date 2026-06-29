function Get-SPSSecret {
    <#
        .SYNOPSIS
        Loads secrets.psd1 and returns a PSCredential for the requested key.

        .DESCRIPTION
        Reads the secrets.psd1 file under the given Config folder and decrypts
        the SecureString stored under the requested CredentialKey to build a
        PSCredential. This replaces the previous Windows Credential Manager
        (credentialmanager module) storage.

        PasswordSecure values must be created with ConvertFrom-SecureString,
        which on Windows uses DPAPI keyed by the current user account on the
        current machine. As a result, secrets.psd1 is only usable by the same
        Windows account that generated its values (typically the InstallAccount
        that runs the SPSUpdate scheduled tasks).

        Returns $null when secrets.psd1 is missing or the key is absent, so the
        caller can surface a clear remediation message.

        .PARAMETER CredentialKey
        Key under the root hashtable of secrets.psd1 (matches CredentialKey in
        the environment config).

        .PARAMETER ConfigPath
        Optional folder containing secrets.psd1. Defaults to src/Config next to
        the module.

        .EXAMPLE
        $cred = Get-SPSSecret -CredentialKey 'PROD-ADM' -ConfigPath $pathConfigFolder
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialKey',
        Justification = 'CredentialKey is a lookup key into secrets.psd1, not a password. The actual secret is decrypted from a DPAPI SecureString and returned as a PSCredential.')]
    [OutputType([System.Management.Automation.PSCredential])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CredentialKey,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    if ([string]::IsNullOrEmpty($ConfigPath)) {
        $ConfigPath = Get-SPSConfigRoot
    }

    $file = Join-Path -Path $ConfigPath -ChildPath 'secrets.psd1'

    if (-not (Test-Path -Path $file)) {
        Write-Verbose -Message "Secrets file not found at '$file'."
        return $null
    }

    $secrets = Import-PowerShellDataFile -Path $file

    if (-not $secrets.ContainsKey($CredentialKey)) {
        Write-Verbose -Message "Secret entry '$CredentialKey' not found in '$file'."
        return $null
    }

    $entry = $secrets[$CredentialKey]

    if ([string]::IsNullOrEmpty($entry.Username)) {
        throw "Secret entry '$CredentialKey' has no Username defined in '$file'."
    }
    if ([string]::IsNullOrEmpty($entry.PasswordSecure) -or $entry.PasswordSecure -like 'PASTE-*') {
        throw "Secret entry '$CredentialKey' has no real PasswordSecure value in '$file'. Generate one with: Read-Host -AsSecureString | ConvertFrom-SecureString"
    }

    try {
        $secureString = ConvertTo-SecureString -String $entry.PasswordSecure -ErrorAction Stop
    }
    catch {
        throw "Failed to decode SecureString for secret '$CredentialKey'. The value must be the output of ConvertFrom-SecureString on the current user account and machine. Original error: $($_.Exception.Message)"
    }

    return New-Object System.Management.Automation.PSCredential($entry.Username, $secureString)
}
