@{
    # =================================================================================
    # SPSUpdate - secrets configuration (example)
    #
    # Copy this file to secrets.psd1 (same Config folder) and replace the placeholder
    # with a real encrypted value. The real secrets.psd1 is gitignored and MUST NEVER
    # be committed to version control.
    #
    # Each key (e.g. 'PROD-ADM') matches the CredentialKey of an environment config
    # (CONTOSO-PROD-CONTENT.psd1). PasswordSecure must be a SecureString encrypted with
    # the current user's DPAPI key. Generate it ON THE TARGET SERVER, signed in as the
    # InstallAccount that will run the scheduled tasks, with:
    #
    #   PS> Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
    #
    # Paste the resulting string between the single quotes below. The encrypted value
    # can only be decrypted by the same user account on the same machine.
    #
    # Tip: running  .\SPSUpdate.ps1 -Action Install -InstallAccount (Get-Credential) ...
    # AS that InstallAccount writes this entry for you automatically.
    # =================================================================================
    'PROD-ADM' = @{
        Username       = 'CONTOSO\svc_spsupdate'
        PasswordSecure = 'PASTE-ConvertFrom-SecureString-OUTPUT-HERE'
    }
}
