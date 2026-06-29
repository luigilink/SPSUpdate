function Set-SPSSecret {
    <#
        .SYNOPSIS
        Writes, updates or removes a credential entry in secrets.psd1.

        .DESCRIPTION
        Set-SPSSecret persists a service credential as a DPAPI-encrypted
        SecureString in secrets.psd1, replacing the previous Windows Credential
        Manager (credentialmanager module) storage. It encrypts
        Credential.Password with ConvertFrom-SecureString (DPAPI keyed to the
        current account/machine on Windows) so only the same account can later
        decrypt it via Get-SPSSecret.

        Existing entries for other keys are preserved. The file is (re)written as
        UTF-8 with BOM so Windows PowerShell 5.1 reads it correctly. secrets.psd1
        is gitignored and must never be committed.

        Run -Action Install as the InstallAccount that will run the scheduled
        tasks, so the DPAPI blob is decryptable at run time.

        .PARAMETER CredentialKey
        Key under the root hashtable of secrets.psd1 (matches CredentialKey in
        the environment config).

        .PARAMETER Credential
        The credential to store. Required unless -Remove is specified.

        .PARAMETER ConfigPath
        Folder containing secrets.psd1. Defaults to src/Config next to the
        module. Created if missing.

        .PARAMETER Remove
        Remove the entry for CredentialKey instead of writing it.

        .EXAMPLE
        Set-SPSSecret -CredentialKey 'PROD-ADM' -Credential $InstallAccount -ConfigPath $pathConfigFolder

        .EXAMPLE
        Set-SPSSecret -CredentialKey 'PROD-ADM' -Remove -ConfigPath $pathConfigFolder
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialKey',
        Justification = 'CredentialKey is a lookup key into secrets.psd1, not a password. The secret itself is supplied as a PSCredential and stored as a DPAPI SecureString.')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CredentialKey,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [System.String]
        $ConfigPath,

        [Parameter()]
        [switch]
        $Remove
    )

    if ([string]::IsNullOrEmpty($ConfigPath)) {
        $ConfigPath = Get-SPSConfigRoot
    }
    if (-not (Test-Path -Path $ConfigPath)) {
        $null = New-Item -Path $ConfigPath -ItemType Directory -Force
    }

    $file = Join-Path -Path $ConfigPath -ChildPath 'secrets.psd1'

    # Load existing entries so other keys are preserved.
    $secrets = @{}
    if (Test-Path -Path $file) {
        $existing = Import-PowerShellDataFile -Path $file
        foreach ($k in $existing.Keys) {
            $secrets[$k] = $existing[$k]
        }
    }

    if ($Remove) {
        if (-not $secrets.ContainsKey($CredentialKey)) {
            Write-Verbose -Message "Secret '$CredentialKey' not present in '$file'; nothing to remove."
            return
        }
        if (-not $PSCmdlet.ShouldProcess($CredentialKey, "Remove secret from $file")) {
            return
        }
        $secrets.Remove($CredentialKey)
    }
    else {
        if ($null -eq $Credential) {
            throw 'Set-SPSSecret requires -Credential when -Remove is not specified.'
        }
        if (-not $PSCmdlet.ShouldProcess($CredentialKey, "Write secret to $file")) {
            return
        }
        $passwordSecure = ConvertFrom-SecureString -SecureString $Credential.Password
        $secrets[$CredentialKey] = @{
            Username       = $Credential.UserName
            PasswordSecure = $passwordSecure
        }
    }

    # Serialize the hashtable back to a .psd1 document.
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('@{')
    foreach ($key in ($secrets.Keys | Sort-Object)) {
        $entry = $secrets[$key]
        $safeKey = $key -replace "'", "''"
        $safeUser = ([string]$entry.Username) -replace "'", "''"
        $safePwd = ([string]$entry.PasswordSecure) -replace "'", "''"
        [void]$builder.AppendLine(("    '{0}' = @{{" -f $safeKey))
        [void]$builder.AppendLine(("        Username       = '{0}'" -f $safeUser))
        [void]$builder.AppendLine(("        PasswordSecure = '{0}'" -f $safePwd))
        [void]$builder.AppendLine('    }')
    }
    [void]$builder.AppendLine('}')

    $content = ($builder.ToString() -replace "`r`n", "`n") -replace "`n", "`r`n"
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($file, $content, $encoding)
}
