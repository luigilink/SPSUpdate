# SPSUpdate - SharePoint Cumulative Update Tool

SPSUpdate is a PowerShell script tool designed to install cumulative updates and run SPConfig.exe in your SharePoint environment.

## Key Features

- Loads environment settings from the JSON config (ApplicationName, ConfigurationName, Domain, FarmName, UpgradeContentDatabase, SideBySideToken, StoredCredential, etc.).
- Logging & diagnostics: Creates Logs folder and per-run log file (sequence-aware naming); starts a transcript (Start-Transcript) for full output capture.
- Safety checks: Verifies script is running with Administrator rights before proceeding.
- SharePoint integration: Detects installed SharePoint version (Get-SPSInstalledProductVersion) and loads the appropriate SharePoint snap-in or module.
- Credential management: Integrates with Credential Manager (via CredentialManager module) to store/retrieve the credential referenced by the JSON config.
- Scheduled-task driven parallelism: Uses helper functions (Add-SPSScheduledTask, Start-SPSScheduledTask, Remove-SPSScheduledTask) to create and run scheduled task
- Full-run mode creates 4 sequence tasks (SPSUpdate-Sequence1..4) and starts them in parallel (with random short sleeps to avoid OWSTimer conflicts).
- SPConfig execution & SideBySide handling: Runs Start-SPSConfigExe locally and Start-SPSConfigExeRemote for other servers; configures SideBySide token (Set-SPSSideBySideToken) and copies side-by-side files remotely if enabled.
- Robust error handling: Extensive try/catch blocks with clear error messages to surface failures per operation (module import, scheduled-task registration/start, credential operations, DB upgrades).
- Helper module usage: Relies on util.psm1 for utility functions (task registration, scheduled task start, Get-SPSInstalledProductVersion, remote invocation helpers).

For details on usage, configuration, and parameters, explore the links below:

- [Getting Started](./Getting-Started)
- [Configuration](./Configuration)
- [Usage](./Usage)
