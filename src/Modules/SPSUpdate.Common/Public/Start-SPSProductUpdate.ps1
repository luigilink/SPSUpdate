function Start-SPSProductUpdate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Nullable[int]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SetupFile,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $ShutdownServices,

        [Parameter()]
        [ValidateSet('Basic', 'Extended')]
        [System.String]
        $ServiceShutdownProfile = 'Basic',

        [Parameter()]
        [System.Boolean]
        $GracefulStopDistributedCache = $false
    )

    Write-Verbose -Message "Getting install status of SP binaries"
    Write-Verbose -Message "Check if the setup file exists"
    if (-Not (Test-Path -Path $SetupFile)) {
        Throw "ERROR: Setup files could not be found: $SetupFile"
    }

    Write-Verbose -Message "Checking file status of $SetupFile"
    Write-Verbose -Message "Checking status now"
    try {
        $zone = Get-Item -Path $SetupFile -Stream "Zone.Identifier" -EA SilentlyContinue
    }
    catch {
        Write-Verbose -Message 'Encountered error while reading file stream. Ignoring file stream.'
    }

    if ($null -ne $zone) {
        $catchMessage = @"
Setup file is blocked! Please use 'Unblock-File -Path $SetupFile' to unblock the file before continuing.
"@
        Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSProductUpdate' -EntryType 'Error'
        throw $catchMessage
    }
    Write-Verbose -Message "File not blocked, continuing."
    Write-Verbose -Message "Get file information from setup file"
    $setupFileInfo = Get-ItemProperty -Path $SetupFile
    $fileVersion = $setupFileInfo.VersionInfo.FileVersion
    Write-Verbose -Message "Update has version $fileVersion"
    $fileVersionInfo = New-Object -TypeName System.Version -ArgumentList $fileVersion

    Write-Verbose -Message "Update is a Cumulative Update."
    # Subscription Edition cumulative update package.
    $setupFileInformation = New-Object -TypeName System.IO.FileInfo -ArgumentList  $SetupFile
    if ($setupFileInformation.Name.StartsWith("wssloc")) {
        Write-Verbose -Message "Cumulative Update is multilingual"
        $versionInfo = Get-SPSLocalVersionInfo -IsWssPackage
    }
    else {
        Write-Verbose -Message "Cumulative Update is generic"
        $versionInfo = Get-SPSLocalVersionInfo
    }

    Write-Verbose -Message "The lowest version of any SharePoint component is $($versionInfo)"
    if ($versionInfo -lt $fileVersionInfo) {
        # Version of SharePoint is lower than the patch version. Patch is not installed.
        Write-Verbose -Message "The version of SharePoint installed is lower than the update. Starting update process."
        $serviceState = $null
        if ($ShutdownServices) {
            $serviceStateFolder = if ([string]::IsNullOrEmpty($script:ModuleRoot)) { Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'SPSUpdate' }
            else { Join-Path -Path (Split-Path -Parent (Split-Path -Parent $script:ModuleRoot)) -ChildPath 'Results' }
            Write-Verbose -Message "Stopping services to speed up installation process (profile $ServiceShutdownProfile)"
            $serviceState = Stop-SPSUpdateServices -ShutdownProfile $ServiceShutdownProfile `
                -GracefulStopDistributedCache $GracefulStopDistributedCache `
                -StateFolder $serviceStateFolder
        }

        try {
            $setupInstall = Start-Process -FilePath $SetupFile -ArgumentList '/passive' -Wait -PassThru
            # Error codes: https://aka.ms/installerrorcodes
            switch ($setupInstall.ExitCode) {
                0 {
                    Write-Verbose -Message "SharePoint update binary installation complete."
                }
                17022 {
                    Write-Verbose -Message ("SharePoint update binary installation complete, however a reboot is required.")
                }
                17025 {
                    Write-Verbose -Message ("The SharePoint update was already installed on your system." + `
                            "Please report an issue about this behavior at https://github.com/dsccommunity/SharePointDsc")
                }
                Default {
                    $catchMessage = @"
SharePoint update install failed, exit code was $($setupInstall.ExitCode).
Error codes can be found at https://aka.ms/installerrorcodes
"@
                    Add-SPSUpdateEvent -Message $catchMessage -Source 'Start-SPSProductUpdate' -EntryType 'Error'
                    throw $catchMessage
                }
            }
        }
        finally {
            # Always put the services back, also when the installer failed.
            if ($null -ne $serviceState -and -not [string]::IsNullOrEmpty($serviceState.Path)) {
                $null = Restore-SPSUpdateServices -Path $serviceState.Path
            }
        }
        return [int]$setupInstall.ExitCode
    }
    else {
        # Version of SharePoint is equal or greater than the patch version. Patch is installed.
        Write-Verbose -Message "The version of SharePoint installed is equal or higher than the update. No action needed."
        return $null
    }
}
