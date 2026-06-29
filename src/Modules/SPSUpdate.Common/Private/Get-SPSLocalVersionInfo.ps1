function Get-SPSLocalVersionInfo {
    [OutputType([System.Version])]
    param
    (
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [ValidateSet('2016', '2019', 'SE')]
        [System.String]
        $ProductVersion,

        [Parameter()]
        [Switch]
        $IsWssPackage
    )

    if ($ProductVersion -eq 'SE') {
        $spVersion = 'Subscription Edition'
    }
    else {
        $spVersion = $ProductVersion
    }

    $productNameRegEx = "Microsoft SharePoint (Foundation|Server) $($spVersion) Core"
    if ($IsWssPackage) {
        $productNameRegEx = "Microsoft SharePoint (Foundation|Server) $($spVersion) \d{4} (Lang|Language) Pack"
    }
    Write-Verbose "Product Name RegEx: $($productNameRegEx)"
    $installerRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products"
    $patchRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Patches"
    $installerEntries = Get-ChildItem -Path $installerRegistryPath -ErrorAction SilentlyContinue
    $nullVersion = New-Object -TypeName System.Version
    $versionInfoValue = New-Object -TypeName System.Version
    $officeProductKeys = $installerEntries | Where-Object -FilterScript { $_.PsPath -like "*00000000F01FEC" }

    if ($null -eq $installerEntries -or $null -eq $officeProductKeys ) {
        return $nullVersion
    }

    # $null - one command returns an empty value
    $null = $officeProductKeys | ForEach-Object -Process {
        $officeProductKey = $_
        $productInfo = Get-ItemProperty "Registry::$($officeProductKey)\InstallProperties" -ErrorAction SilentlyContinue
        if ($null -eq $productInfo) {
            return
        }
        $prodName = $productInfo.DisplayName
        if ($prodName -match $productNameRegEx) {
            Write-Verbose "Gathering Information for $($prodName)"
            $versionInfo = $nullVersion
            $patchInformationFolder = Get-ItemProperty "Registry::$($officeProductKey)\Patches"
            $patchGuid = $patchInformationFolder.AllPatches
            if ($null -ne $patchGuid) {
                $detailedPatchInformation = Get-ItemProperty "$($patchRegistryPath)\$($patchGuid)" -ErrorAction SilentlyContinue
                $localPackage = $detailedPatchInformation.LocalPackage
                if ($null -ne $localPackage) {
                    $patchFileInformation = New-Object -TypeName System.IO.FileInfo -ArgumentList $localPackage
                    if ($patchFileInformation.Extension -eq ".msp") {
                        try {
                            $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
                            $installerDatabase = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, ($localPackage , 32))
                            $databaseQuery = "SELECT Value FROM MsiPatchMetadata WHERE Property = 'BuildNumber'"
                            $databaseView = $installerDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $installerDatabase, ($databaseQuery))
                            $databaseView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $databaseView, $null)
                            $value = $databaseView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $databaseView, $null)
                            $versionInfo = [System.Version]$value.GetType().InvokeMember("StringData", "GetProperty", $null, $value, 1)
                            Clear-ComObject -ComObject $databaseView
                            Clear-ComObject -ComObject $value
                            Clear-ComObject -ComObject $installerDatabase
                            Clear-ComObject -ComObject $windowsInstaller
                        }
                        catch [Exception] {
                            $catchMessage = @"
An error occurred during the collection of data about installed products in Get-SPSLocalVersionInfo.
Exception: $($_.Exception.Message)
"@
                            Write-Error -Message $catchMessage
                            Add-SPSUpdateEvent -Message $catchMessage -Source 'Get-SPSLocalVersionInfo' -EntryType 'Error'
                            $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                        }
                    }
                    else {
                        $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                    }
                }
                else {
                    $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
                }
            }
            else {
                $versionInfo = New-Object -TypeName System.Version -ArgumentList $productInfo.DisplayVersion
            }
            # Collect Information about language packs
            if ($IsWssPackage -and (  $versionInfoValue -eq $nullVersion -or $versionInfoValue -gt $versionInfo)) {
                $versionInfoValue = $versionInfo
            }
            else {
                $versionInfoValue = $versionInfo
            }
            Write-Verbose "Version Information for $($prodName): $($versionInfoValue)"
        }
    }

    if ($nullVersion -ne $versionInfoValue) {
        return $versionInfoValue
    }

    return $nullVersion
}
