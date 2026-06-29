@{
    RootModule        = 'SPSUpdate.Common.psm1'
    ModuleVersion     = '4.0.0'
    GUID              = 'd6f4e2b7-3a1c-4d8e-9f2a-6c5b7e0a1d34'
    Author            = 'Jean-Cyril DROUHIN'
    CompanyName       = 'luigilink'
    Copyright         = '(c) Jean-Cyril DROUHIN. All rights reserved.'
    Description       = 'Shared functions for the SPSUpdate toolkit (install SharePoint Server cumulative updates: product update, PSConfig, content database mount/upgrade, side-by-side token, scheduled tasks and DPAPI secret helpers).'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Add-SPSScheduledTask'
        'Add-SPSUpdateEvent'
        'Copy-SPSSideBySideFilesRemote'
        'Get-SPSInstalledProductVersion'
        'Get-SPSSecret'
        'Get-SPSServersPatchStatus'
        'Initialize-SPSContentDbJsonFile'
        'Mount-SPSContentDatabase'
        'Remove-SPSScheduledTask'
        'Set-SPSSecret'
        'Set-SPSSideBySideToken'
        'Start-SPSConfigExe'
        'Start-SPSConfigExeRemote'
        'Start-SPSProductUpdate'
        'Start-SPSScheduledTask'
        'Test-SPSPendingReboot'
        'Update-SPSContentDatabase'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Copy-SPSSideBySideFilesAllServers')

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointServer', 'CumulativeUpdate', 'Patching', 'PSConfig', 'ContentDatabase')
            LicenseUri   = 'https://github.com/luigilink/SPSUpdate/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/luigilink/SPSUpdate'
            ReleaseNotes = 'https://github.com/luigilink/SPSUpdate/blob/main/RELEASE-NOTES.md'
        }
    }
}
