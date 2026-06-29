@{
    # =================================================================================
    # SPSUpdate - environment configuration (example)
    #
    # Copy this file to a real config (e.g. CONTOSO-PROD-CONTENT.psd1) and edit the
    # values for your environment, then run:
    #   .\SPSUpdate.ps1 -ConfigFile 'CONTOSO-PROD-CONTENT.psd1'
    #
    # Real config files (Config\*.psd1) are gitignored so internal infrastructure
    # details (server names, domains, build versions) never land in version control.
    # Only this *.example.psd1 template is committed.
    #
    # Convention: keep one config file per farm (CONTENT, SEARCH, SERVICES, ...). The
    # keys below are identical across farms; only the values change.
    # =================================================================================

    # --- Identity (all REQUIRED) -----------------------------------------------------

    # ConfigurationName : free-form environment identifier. Used in log/result file names.
    # Possible values   : any string, e.g. 'PROD', 'PPRD', 'PREPROD', 'DEV', 'TEST'.
    ConfigurationName      = 'PROD'

    # ApplicationName : free-form application/customer code. Used in log/result file names.
    # Possible values : any string, e.g. 'contoso'.
    ApplicationName        = 'contoso'

    # FarmName : logical name of the farm targeted by this config. Used in logs and in
    # the generated ContentDB inventory file name (<App>-<Env>-<FarmName>-ContentDBs.json).
    # Possible values : any string, e.g. 'CONTENT', 'SEARCH', 'SERVICES'.
    FarmName               = 'CONTENT'

    # Domain : DNS suffix appended to each farm server short name when remoting (CredSSP).
    # Possible values : any AD DNS domain, e.g. 'contoso.com', 'corp.contoso.local'.
    Domain                 = 'contoso.com'

    # CredentialKey : name of the entry in Config\secrets.psd1 holding the InstallAccount
    # used for CredSSP remoting and to run the scheduled tasks. Populate it by running
    # -Action Install as that account, or manually (see secrets.example.psd1).
    # Possible values : any key present in secrets.psd1, e.g. 'PROD-ADM'.
    CredentialKey          = 'PROD-ADM'

    # StatusStorePath : OPTIONAL UNC share where every server writes its patching
    # progress so the live HTML dashboard can be assembled (near real-time tracking,
    # v4.2.0+). It must be writable by the InstallAccount from every farm server.
    # Leave empty/omit to fall back to the local Results\status folder (in that case
    # ProductUpdate runs on other servers are not captured in the master dashboard).
    # Possible values : '' or a UNC path, e.g. '\\fileserver\spsupdate-status'.
    StatusStorePath        = '\\fileserver\spsupdate-status'

    # --- Binaries (REQUIRED block; used by -Action ProductUpdate) ---------------------
    Binaries               = @{
        # ProductUpdate : allow the binary installation step.
        # Possible values : $true | $false.   Default if omitted: $true
        ProductUpdate    = $true

        # SetupFullPath : folder (local to each server) that holds the update binaries.
        # Possible values : any absolute Windows path.
        SetupFullPath    = 'D:\SoftwarePackages\SPS\cumulativeupdates'

        # SetupFileName : update executable(s), installed in the listed order. Provide a
        # single uber package, or the STS + WSSLOC (language) pair.
        # Possible values : array of .exe file names located under SetupFullPath.
        SetupFileName    = @(
            'uber-subscription-kb5002651-fullfile-x64-glb.exe'
            # 'sts-subscription-kb5002191-fullfile-x64-glb.exe'
            # 'wssloc-subscription-kb5002110-fullfile-x64-glb.exe'
        )

        # ShutdownServices : stop Search/Timer/IIS services during install to speed it up
        # (they are restored to their prior state afterwards).
        # Possible values : $true | $false.   Default if omitted: $true
        ShutdownServices = $false
    }

    # --- Content database handling (OPTIONAL) ----------------------------------------

    # MountContentDatabase : mount the databases listed in the generated ContentDB
    # inventory (typically for a SP2019 -> Subscription Edition migration). When either
    # this or UpgradeContentDatabase is $true, the inventory JSON is (re)built on run.
    # Possible values : $true | $false.   Default if omitted: $false
    MountContentDatabase   = $false

    # UpgradeContentDatabase : run Upgrade-SPContentDatabase on databases that NeedsUpgrade.
    # Possible values : $true | $false.   Default if omitted: $true
    UpgradeContentDatabase = $true

    # --- Side-by-side patching (OPTIONAL block) --------------------------------------
    SideBySideToken        = @{
        # Enable : turn EnableSideBySide on the web applications and copy side-by-side files.
        # Possible values : $true | $false.   Default if omitted: $false
        Enable       = $false

        # BuildVersion : the side-by-side token build. Leave empty to skip token config.
        # Possible values : '' or a SharePoint build, e.g. '16.0.17928.20238'.
        BuildVersion = ''
    }
}
