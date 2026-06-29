function Start-SPSProductUpdate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SetupFile,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $ShutdownServices
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
    if ($fileVersionInfo.Build.ToString().Length -eq 4) {
        $sharePointVersion = '2016'
    }
    else {
        if ($fileVersionInfo.Build -lt 13000) {
            $sharePointVersion = '2019'
        }
        else {
            $sharePointVersion = 'SE'
        }
    }

    Write-Verbose -Message "Update is a Cumulative Update."
    # For SP 2016 + 2019 Patches
    $setupFileInformation = New-Object -TypeName System.IO.FileInfo -ArgumentList  $SetupFile
    if ($setupFileInformation.Name.StartsWith("wssloc")) {
        Write-Verbose -Message "Cumulative Update is multilingual"
        $versionInfo = Get-SPSLocalVersionInfo -ProductVersion $sharePointVersion -IsWssPackage
    }
    else {
        Write-Verbose -Message "Cumulative Update is generic"
        $versionInfo = Get-SPSLocalVersionInfo -ProductVersion $sharePointVersion
    }

    Write-Verbose -Message "The lowest version of any SharePoint component is $($versionInfo)"
    if ($versionInfo -lt $fileVersionInfo) {
        # Version of SharePoint is lower than the patch version. Patch is not installed.
        Write-Verbose -Message "The version of SharePoint installed is lower than the update. Starting update process."
        $installedVersion = Get-SPSInstalledProductVersion
        if ($ShutdownServices) {
            $listOfServices = @("SPSearchHostController", "SPTimerV4", "IISADMIN")
            if ($installedVersion.ProductMajorPart -eq 15) {

                $listOfServices += "OSearch15"
            }
            else {
                $listOfServices += "OSearch16"
            }
            Write-Verbose -Message "Gettings services status before stopping services for installation."
            $servicesStatusFilePath = Join-Path -Path $PSScriptRoot -ChildPath "ServicesStatus_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMddHHmmss').json"
            Get-Service -Name $listOfServices -ErrorAction SilentlyContinue | Select-Object Name, StartType, Status | ConvertTo-Json | Set-Content -Path $servicesStatusFilePath -Force
            Write-Verbose -Message "Services status saved to $servicesStatusFilePath"
            Write-Verbose -Message "Stopping services to speed up installation process"
            foreach ($service in $listOfServices) {
                Write-Verbose -Message "Stopping service: $service - Setting startup type to disabled"
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            }
            write-Verbose -Message "All services stopped. Starting installation process."
            $null = Start-Process -FilePath "iisreset.exe" `
                -ArgumentList "-stop -noforce" `
                -Wait `
                -PassThru


        }

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
        if ($ShutdownServices) {
            Write-Verbose -Message "Getting services status from json configuration."
            $servicesStatusFromFile = Get-Content -Path $servicesStatusFilePath -Raw | ConvertFrom-Json
            foreach ($service in $servicesStatusFromFile) {
                Write-Verbose -Message "Service: $($service.Name) - Startup Type before installation: $($service.StartType) - Status before installation: $($service.Status)"
                if ($service.Status -ne "Running") {
                    Write-Verbose -Message "Service: $($service.Name) was not running before installation. Keeping it stopped."
                    Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose -Message "Service: $($service.Name) was running before installation. Restoring its startup type."
                    Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction SilentlyContinue
                    Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                }
            }
            Start-Process -FilePath "iisreset.exe" `
                -ArgumentList "-start" `
                -Wait `
                -PassThru
            write-Verbose -Message "All services started. Installation process complete."
        }
    }
    else {
        # Version of SharePoint is equal or greater than the patch version. Patch is installed.
        Write-Verbose -Message "The version of SharePoint installed is equal or higher than the update. No action needed."
    }
}
