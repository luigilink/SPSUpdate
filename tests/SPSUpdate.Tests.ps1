# Resolve repo root - works on CI/CD (GitHub Actions)

Describe 'SPSUpdate.ps1 File Existence' {
    It 'SPSUpdate.ps1 exists' -Skip:(-not $IsWindows) {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        Test-Path -Path $scriptPath -PathType Leaf | Should -Be $true
    }

    It 'is a PowerShell script file' -Skip:(-not $IsWindows) {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptPath | Should -Match '\.ps1$'
    }

    It 'has valid PowerShell syntax' -Skip:(-not $IsWindows) {
        $parseErrors = $null
        $tokens = $null
        
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $null = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Path $scriptPath -Raw), [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
    }
}

Describe 'SPSUpdate.ps1 Configuration Validation' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'contains Test-ConfigurationFile function' {
        $scriptContent | Should -Match 'function Test-ConfigurationFile'
    }

    It 'validates required configuration properties' {
        $scriptContent | Should -Match 'ApplicationName|ConfigurationName|Domain|FarmName|StoredCredential'
    }

    It 'checks for missing properties' {
        $scriptContent | Should -Match 'Get-Member.*NoteProperty'
    }

    It 'validates non-empty property values' {
        $scriptContent | Should -Match 'IsNullOrWhiteSpace'
    }

    It 'parses JSON configuration' {
        $scriptContent | Should -Match 'ConvertFrom-Json'
    }
}

Describe 'SPSUpdate.ps1 Task Name Constants' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'defines TaskNameFullScript constant' {
        $scriptContent | Should -Match '\$script:TaskNameFullScript\s*=\s*[''"]SPSUpdate-FullScript[''"]'
    }

    It 'defines TaskNameSequencePrefix constant' {
        $scriptContent | Should -Match '\$script:TaskNameSequencePrefix\s*=\s*[''"]SPSUpdate-Sequence[''"]'
    }

    It 'defines TaskPath constant' {
        $scriptContent | Should -Match '\$script:TaskPath\s*=\s*[''"]SharePoint[''"]'
    }

    It 'uses constants in Uninstall action' {
        $scriptContent | Should -Match '(?s)''Uninstall''\s*\{.*Remove-SPSScheduledTask -Name \$script:TaskNameFullScript -TaskPath \$script:TaskPath'
    }

    It 'uses constants in Install action' {
        $scriptContent | Should -Match '(?s)''Install''\s*\{.*Add-SPSScheduledTask -Name \$script:TaskNameFullScript.*-TaskPath \$script:TaskPath'
    }
}

Describe 'SPSUpdate.ps1 Scheduled Task Existence Check' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'checks if task already exists before creating' {
        $scriptContent | Should -Match 'Get-ScheduledTask.*existingTask|existingTask.*Get-ScheduledTask'
    }

    It 'warns when task exists' {
        $scriptContent | Should -Match 'Write-Warning.*already exists'
    }

    It 'removes existing task before recreating' {
        $scriptContent | Should -Match '\$null\s*-ne\s*\$existingTask(?s:.*?)Remove-SPSScheduledTask'
    }

    It 'uses existence check in Install action' {
        $scriptContent | Should -Match '(?s)''Install''\s*\{.*Get-ScheduledTask -TaskName \$script:TaskNameFullScript -TaskPath "\\\$script:TaskPath\\"'
    }

    It 'uses existence check in Default action' {
        $scriptContent | Should -Match '(?s)Default\s*\{.*Get-ScheduledTask -TaskName \$taskName -TaskPath "\\\$script:TaskPath\\"'
    }
}

Describe 'SPSUpdate.ps1 Default Action Task Management' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'Default action uses task name variables for Sequence tasks' {
        $scriptContent | Should -Match '\$taskName\s*=\s*"\$script:TaskNameSequencePrefix\$taskId"'
    }

    It 'Default action passes -TaskPath to Start-SPSScheduledTask' {
        $scriptContent | Should -Match 'Start-SPSScheduledTask.*-TaskPath\s*\$script:TaskPath'
    }

    It 'Default action captures start result and enforces ErrorAction Stop' {
        $scriptContent | Should -Match '\$startResult\s*=\s*Start-SPSScheduledTask\s+-Name\s+\$taskName\s+-TaskPath\s+\$script:TaskPath\s+-ErrorAction\s+Stop'
    }

    It 'Default action queries scheduled task state with TaskPath' {
        $scriptContent | Should -Match 'Get-ScheduledTask\s+-TaskName\s+\$scheduledTask\s+-TaskPath\s+"\\\$script:TaskPath\\"'
    }

    It 'Default action treats Queued tasks as still active' {
        $scriptContent | Should -Match '\$taskStatus\.State\s+-ne\s+''Running''\s+-and\s+\$taskStatus\.State\s+-ne\s+''Queued'''
    }

    It 'Default action passes -TaskPath to Add-SPSScheduledTask' {
        $scriptContent | Should -Match '(?s)Default\s*\{.*Add-SPSScheduledTask -Name \$taskName.*-TaskPath \$script:TaskPath' -Because 'Default action should use TaskPath constant when adding sequence tasks'
    }

    It 'Default action logs task errors to event log' {
        $scriptContent | Should -Match '(?s)Default\s*\{.*Add-SPSUpdateEvent -Message \$catchMessage -Source ''Add-SPSScheduledTask'' -EntryType ''Error''.*Add-SPSUpdateEvent -Message \$catchMessage -Source ''Start-SPSScheduledTask'' -EntryType ''Error''' -Because 'Default action should log scheduled task failures to event log'
    }

    It 'uses consistent task name format in task list' {
        $scriptContent | Should -Match '(?s)\$scheduledTasks\s*=\s*@\(\s*"\$script:TaskNameSequencePrefix`1"' -Because 'Task list should use script constant for task names'
    }
}

Describe 'SPSUpdate.ps1 Error Logging' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'uses catchMessage variables before writing errors' {
        $scriptContent | Should -Match '\$catchMessage\s*=\s*@"' -Because 'Current error handling pattern builds a reusable catchMessage string'
    }

    It 'logs initialization failures to the event log' {
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Get-SPSInstalledProductVersion'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Initialize-SPSContentDbJsonFile'' -EntryType ''Error'''
    }

    It 'logs install and uninstall task failures to the event log' {
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Remove-SPSScheduledTask'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Add-SPSScheduledTask'' -EntryType ''Error'''
    }

    It 'logs product update and credential failures to the event log' {
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Start-SPSProductUpdate'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Get-StoredCredential'' -EntryType ''Error'''
    }

    It 'logs configuration wizard and side-by-side failures to the event log' {
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Start-SPSConfigExe'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Start-SPSConfigExeRemote'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Set-SPSSideBySideToken'' -EntryType ''Error'''
        $scriptContent | Should -Match 'Add-SPSUpdateEvent -Message \$catchMessage -Source ''Copy-SPSSideBySideFiles'' -EntryType ''Error'''
    }
}

Describe 'SPSUpdate.ps1 Content Validation' {
    BeforeAll {
        $scriptPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/SPSUpdate.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction SilentlyContinue
    }

    It 'contains param block' {
        $scriptContent | Should -Match 'param\s*\('
    }

    It 'defines the current script version' {
        $scriptContent | Should -Match '\$SPSUpdateVersion\s*=\s*''3\.2\.0'''
    }

    It 'imports util module' {
        $scriptContent | Should -Match 'Import-Module.*util\.psm1|Import-Module.*util'
    }

    It 'imports credentialmanager module' {
        $scriptContent | Should -Match 'CredentialManager\.psd1|Import-Module.*credentialmanager'
    }

    It 'uses Start-Transcript for logging' {
        $scriptContent | Should -Match 'Start-Transcript'
    }

    It 'guards Stop-Transcript behind TranscriptStarted state' {
        $scriptContent | Should -Match '\$script:TranscriptStarted\s*=\s*\$false'
        $scriptContent | Should -Match 'if\s*\(\$script:TranscriptStarted\)\s*\{\s*Stop-Transcript'
    }

    It 'contains try-catch error handling' {
        $scriptContent | Should -Match 'try\s*\{|catch\s*\{'
    }

    It 'checks for administrator privileges' {
        $scriptContent | Should -Match 'Administrator'
    }

    It 'does not call Test-SPSPendingReboot in ProductUpdate flow' {
        $scriptContent | Should -Not -Match 'Test-SPSPendingReboot'
    }

    It 'does not contain legacy ProductUpdate MOF cleanup code' {
        $scriptContent | Should -Not -Match 'Cleaning up DSC MOF File|\.mof'
    }

    It 'declares InitContentDB in the Action validateSet' {
        $scriptContent | Should -Match "validateSet\([^)]*'InitContentDB'"
    }

    It 'implements the InitContentDB switch case' {
        $scriptContent | Should -Match "(?s)'InitContentDB'\s*\{.*Initialize-SPSContentDbJsonFile\s+-Path\s+\`$spsUpdateDBsPath"
    }

    It 'invokes Mount-SPSContentDatabase when MountContentDatabase is enabled' {
        $scriptContent | Should -Match '(?s)if\s*\(\s*\$jsonEnvCfg\.MountContentDatabase\s*\).*Mount-SPSContentDatabase'
    }

    It 'loads ContentDatabase json file when MountContentDatabase is enabled' {
        $scriptContent | Should -Match '\$jsonEnvCfg\.UpgradeContentDatabase\s*-or\s*\$jsonEnvCfg\.MountContentDatabase'
    }

    It 'spawns parallel scheduled tasks when MountContentDatabase or UpgradeContentDatabase is enabled' {
        # Loader (top of script), Default master branch and Install branch must all use the OR condition
        ([regex]::Matches($scriptContent, '\$jsonEnvCfg\.UpgradeContentDatabase\s*-or\s*\$jsonEnvCfg\.MountContentDatabase')).Count | Should -BeGreaterOrEqual 3
    }

    It 'gates Update-SPSContentDatabase inside Sequence loop with UpgradeContentDatabase flag' {
        $scriptContent | Should -Match '(?s)if\s*\(\s*\$jsonEnvCfg\.UpgradeContentDatabase\s*\)\s*\{\s*Update-SPSContentDatabase\s+-Name\s+\$db\.Name'
    }

    It 'runs Mount-SPSContentDatabase inside the per-DB Sequence loop (parallel via 4 sequences)' {
        $scriptContent | Should -Match '(?s)foreach\s*\(\s*\$db\s+in\s+\$dbs\s*\)\s*\{[^}]*if\s*\(\s*\$jsonEnvCfg\.MountContentDatabase\s*\)[^}]*Mount-SPSContentDatabase\s+-Name\s+\$db\.Name\s+-WebAppUrl\s+\$db\.WebAppUrl\s+-DatabaseServer\s+\$db\.Server'
    }
}

Describe 'SPSUpdate.ps1 Dependencies' {
    It 'util.psm1 module file exists' -Skip:(-not $IsWindows) {
        $utilPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Modules/util.psm1'
        Test-Path -Path $utilPath -PathType Leaf | Should -Be $true
    }

    It 'sps.util.psm1 module file exists' -Skip:(-not $IsWindows) {
        $spsUtilPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Modules/sps.util.psm1'
        Test-Path -Path $spsUtilPath -PathType Leaf | Should -Be $true
    }

    It 'credentialmanager folder exists' -Skip:(-not $IsWindows) {
        $credPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Modules/credentialmanager'
        Test-Path -Path $credPath -PathType Container | Should -Be $true
    }

    It 'Config folder exists' -Skip:(-not $IsWindows) {
        $configPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Config'
        Test-Path -Path $configPath -PathType Container | Should -Be $true
    }

    It 'sample config files exist' -Skip:(-not $IsWindows) {
        $configPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Config'
        @(Get-ChildItem -Path $configPath -Filter '*.json' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
}

Describe 'Configuration Files' {
    It 'all config files are valid JSON' -Skip:(-not $IsWindows) {
        $configPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Config'
        $configFiles = Get-ChildItem -Path $configPath -Filter '*.json' -ErrorAction SilentlyContinue
        
        foreach ($file in $configFiles) {
            $content = Get-Content -Path $file.FullName -Raw
            { $content | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw -Because "Config file $($file.Name) must be valid JSON"
        }
    }

    It 'config files contain ConfigurationName property' -Skip:(-not $IsWindows) {
        $configPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Config'
        $configFiles = Get-ChildItem -Path $configPath -Filter '*.json' -ErrorAction SilentlyContinue
        
        foreach ($file in $configFiles) {
            $config = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $config.ConfigurationName | Should -Not -BeNullOrEmpty -Because "Config file $($file.Name) must have ConfigurationName property"
        }
    }

    It 'config files contain required properties' -Skip:(-not $IsWindows) {
        $requiredProperties = @('ApplicationName', 'ConfigurationName', 'Domain', 'FarmName', 'StoredCredential')
        $configPath = Join-Path -Path (Get-Location).Path -ChildPath 'scripts/Config'
        $configFiles = Get-ChildItem -Path $configPath -Filter '*.json' -ErrorAction SilentlyContinue
        
        foreach ($file in $configFiles) {
            $config = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            foreach ($prop in $requiredProperties) {
                $config.$prop | Should -Not -BeNullOrEmpty -Because "Config file $($file.Name) must have $prop property"
            }
        }
    }
}
