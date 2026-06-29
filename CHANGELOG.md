# Change log for SPSUpdate

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.2.0] - 2026-06-29

### Added

- Near real-time patching dashboard. New public functions `Set-SPSUpdateStatus` /
  `Get-SPSUpdateStatus` persist and read a shared, per-scope JSON status store
  (atomic writes, each writer owns its file), `Get-SPSStatusCampaignPath` resolves
  the campaign folder, and `Export-SPSUpdateProgressReport` renders a self-contained,
  auto-refreshing HTML dashboard (overall state, per-phase sections, colored state
  badges, per-item exit codes and per-sequence percentage).
- New optional `StatusStorePath` config key (UNC share) for the status store, with a
  local `Results\status` fallback.
- New `-Action ResetStatus` to clear a campaign before a fresh patching round.
- `SPSUpdate.ps1` is instrumented to feed the store and regenerate the dashboard:
  ProductUpdate per server (per-setup-file items), the four mount/upgrade sequences
  (per-database items and a running percentage), the Configuration Wizard per server
  (local and remote), and the side-by-side step. The master regenerates the dashboard
  on every wait-loop iteration and writes a final completed dashboard.
- New `Test-SPSUpdateReadiness.ps1` pre-flight check (module, config, DPAPI secret,
  elevation, status store write access, per-server CredSSP reachability).

### Changed

- Bumped the module manifest to `4.2.0` and exported the four new functions.
- Extended the shared HTML head helper with an optional meta-refresh and state-badge styles.

### Tests

- Added cross-platform Pester suites for the status store round-trip and resilience, and
  for the dashboard (running / failed / completed / empty / HTML-encoding).

## [4.1.0] - 2026-06-29

### Added

- New public function `Export-SPSUpdateDbReport` that renders the ContentDatabase inventory (`<App>-<Env>-<Farm>-ContentDBs.json`) as a self-contained, offline HTML report: summary cards (total databases, total size, balance spread), the per-sequence LPT distribution (count / size / percentage bars), and a sortable, filterable table of every database. Inventories generated before v4.1.0 (no size) still render and fall back to distributing by database count.
- `SPSUpdate.ps1` now writes the HTML report under a new `Results\` folder whenever the inventory is (re)generated (the `InitContentDB` action and the Default-mode prime). Report failures warn but never block the run.
- Private report helpers: `ConvertTo-SPSHtmlEncoded`, `Get-SPSReportCardHtml`, `Get-SPSReportHtmlHead`, `Get-SPSReportDistributionHtml`, `Get-SPSReportHtmlScript`.

### Changed

- `Initialize-SPSContentDbJsonFile` now persists `SizeInBytes` and `SizeInMB` for each database in the inventory JSON. This is backward compatible: the mount/upgrade flow still reads only `Name`, `WebAppUrl` and `Server`.
- Bumped the module manifest to `4.1.0` and exported `Export-SPSUpdateDbReport`.

### Tests

- Added `Export-SPSUpdateDbReport.Tests.ps1` covering the self-contained HTML output, total size and distribution rendering, JSON-payload markup neutralization, the legacy no-size inventory path, reading from a JSON file, and the missing-file error.

## [4.0.0] - 2026-06-29

### Added

- New `SPSUpdate.Common` PowerShell module (`src/Modules/SPSUpdate.Common`) with a manifest-driven version, a dot-sourcing loader, and a one-file-per-function layout split into `Public/` and `Private/`.
- DPAPI credential store: `Get-SPSSecret` / `Set-SPSSecret` persist the `InstallAccount` as an encrypted SecureString in `Config\secrets.psd1`, replacing the Windows Credential Manager module. `-Action Install` writes the secret and `-Action Uninstall` removes it.
- Tolerant configuration loader: optional keys fall back to safe defaults (`Binaries.ProductUpdate`, `Binaries.ShutdownServices` and `UpgradeContentDatabase` default to `$true`; `MountContentDatabase` and `SideBySideToken.Enable` default to `$false`).
- Repository scaffolding aligned with the other SPS* projects: `.editorconfig`, `.gitattributes` (UTF-8 BOM + CRLF for PowerShell files), `PSScriptAnalyzerSettings.psd1`, and an expanded `.gitignore`.
- Wiki: new `Release-Process` page and `_Sidebar.md` navigation.
- Offline install guide (`src/SPSUpdate_README.md`) shipped inside the release ZIP, rewritten for the psd1 config, the DPAPI secret store and the `Modules\` layout (no DSC).

### Changed

- **BREAKING** — Project layout moved from `scripts/` to `src/`. The release ZIP now packages the *contents* of `src/`, so the archive extracts straight to `SPSUpdate.ps1`, `Config\` and `Modules\` (no wrapper folder).
- **BREAKING** — Environment configuration moved from JSON to a PowerShell data file (`*.psd1`), read with `Import-PowerShellDataFile`. A single documented template (`Config\CONTOSO-PROD.example.psd1`) lists every option with its possible values inline. Runtime/output files (the ContentDB inventory and logs) stay JSON by design.
- **BREAKING** — The config key `StoredCredential` is renamed to `CredentialKey` and now points at an entry in `Config\secrets.psd1` instead of a Windows Credential Manager target.
- `SPSUpdate.ps1` now imports `SPSUpdate.Common`, derives its version banner from the module manifest, and reads/writes the InstallAccount credential through `Get-SPSSecret`/`Set-SPSSecret`.
- `Add-SPSUpdateEvent` is now self-contained (version/user resolved from the module) and re-points a mis-mapped event source to the `SPSUpdate` log instead of returning silently.
- CI: `release.yml` zips the contents of `src/`; `pester.yml` triggers on `src/**`, `tests/**` and `PSScriptAnalyzerSettings.psd1`, and runs PSScriptAnalyzer against `src/SPSUpdate.ps1` and the `SPSUpdate.Common` module.
- `README.md` trimmed to a short overview with quick links; the wiki (`Home`, `Getting-Started`, `Configuration`, `Usage`) rewritten for the new layout, psd1 config and DPAPI secret store.

### Fixed

- `Invoke-SPSCommand` now fails fast when the CredSSP `New-PSSession` cannot be established (`-ErrorAction Stop` + a clear `throw`) instead of falling back to running the SharePoint scriptblock **locally** on the master server with no session — which previously made PSConfig and side-by-side operations silently target the wrong server. Added an `OpenTimeout` and clearer remote-failure error messages, aligned with the SPSWeather hardening.

- **BREAKING** — The bundled third-party `credentialmanager` module (DLLs + manifest) and all `Get-/New-/Remove-StoredCredential` usage.
- The legacy `scripts/` tree, including the flat `util.psm1` / `sps.util.psm1` helpers and the per-farm JSON configs.

### Tests

- Replaced the scripts/JSON-oriented Pester tests with a cross-platform suite (`tests/SPSUpdate.Common.Tests.ps1`, `tests/Configuration.Tests.ps1`) covering the manifest, the exact public export set, hidden private helpers, file conventions (one function per file, UTF-8 BOM, parse), parameter contracts, the `Add-SPSUpdateEvent` self-heal, a DPAPI secret round-trip (Windows-only), and the example psd1 config/secret contract.

## [3.2.1] - 2026-06-11

### Changed

scripts/Modules/sps.util.psm1:

- `Initialize-SPSContentDbJsonFile` now distributes content databases across the four sequences using a **Longest Processing Time First (LPT)** algorithm based on `DiskSizeRequired`, instead of splitting them evenly by count (`floor(count / 4)`). Sequences are now balanced by total database size so parallel upgrade workloads finish closer to the same time.
- `Initialize-SPSContentDbJsonFile` now prints a distribution report to the transcript showing the count, total size (MB) and percentage for each of the four sequences.
- `Initialize-SPSContentDbJsonFile` now also writes a timestamped snapshot of the inventory (`<basename>_yyyy-MM-dd_HH-mm-ss.json`) next to the canonical file each time it runs. The canonical file (consumed by `SPSUpdate.ps1`) is still overwritten in place, while the dated snapshots accumulate in `scripts/Config/` so previous inventories can be reviewed or restored. Snapshot failures are logged via `Write-Verbose` and never block the canonical write.
- `Start-SPSProductUpdate` now invokes the SharePoint patch setup with `/passive` instead of `/quiet`. `/passive` still runs the patch without user interaction but displays a progress UI, which gives administrators visibility on the installation progress when the script is run interactively. Behavior of the returned exit code and the post-install service-restoration logic is unchanged.

scripts/SPSUpdate.ps1:

- Bumped `$SPSUpdateVersion` to `3.2.1`.

### Fixed

scripts/Modules/sps.util.psm1:

- Fixed `Initialize-SPSContentDbJsonFile` edge case where fewer than 4 content databases caused `groupSize` to evaluate to `0`, dumping every database into `SPContentDatabase4` and leaving `SPContentDatabase1..3` empty.

### Tests

tests/Modules/sps.util.Tests.ps1:

- Added Pester tests for `Initialize-SPSContentDbJsonFile` covering: no file written when `Get-SPContentDatabase` returns `$null`, fair distribution of fewer than 4 databases (regression for the `floor(count / 4)` bug), LPT balancing by size (the largest database lands alone in its sequence), and the `SPContentDatabase1..4` JSON property contract consumed by `SPSUpdate.ps1`.

## [3.2.0] - 2026-05-26

### Added

scripts/SPSUpdate.ps1:

- Added new `InitContentDB` value for the `Action` parameter that (re)generates the ContentDatabase inventory JSON file for the local farm. Intended to be run on the source farm before a farm upgrade (for example SharePoint Server 2019 → Subscription Edition).
- Added new `MountContentDatabase` configuration property in the JSON config file. When `true`, the master server iterates through the ContentDatabase inventory JSON file and mounts every database that is not already attached to the farm. Mounts are performed sequentially to avoid concurrent writes to the configuration database.
- Loader of the ContentDatabase inventory JSON file now also runs when `MountContentDatabase` is `true` (previously only when `UpgradeContentDatabase` was `true`).
- Added dedicated transcript log file naming for the `InitContentDB` action.

scripts/Modules/sps.util.psm1:

- Added `Mount-SPSContentDatabase` wrapper around `Mount-SPContentDatabase`. The wrapper validates the target web application, skips databases that are already attached, and accepts an optional `DatabaseServer` parameter.

tests/SPSUpdate.Tests.ps1:

- Added assertions for the new `InitContentDB` action and the `MountContentDatabase` flow.
- Added regression test that the ProductUpdate flow no longer calls `Test-SPSPendingReboot`.

tests/Modules/sps.util.Tests.ps1:

- Added tests for `Mount-SPSContentDatabase` (export, parameters, idempotency when the DB is already attached, mounting when missing, error when the web application is not found).

### Changed

scripts/SPSUpdate.ps1:

- Bumped `$SPSUpdateVersion` to `3.2.0`.
- Removed the blocking pending-reboot check from the `ProductUpdate` action. On production farms the Windows reboot markers (Component Based Servicing, `PendingFileRenameOperations`, etc.) commonly remain set after several reboots, which was causing legitimate updates to be aborted. The `Test-SPSPendingReboot` helper is kept available in `util.psm1` for ad-hoc usage.

### Documentation

- Updated `scripts/SPSUpdate_README.md`, `wiki/Configuration.md` and `wiki/Usage.md` to document the new `InitContentDB` action, the new `MountContentDatabase` JSON property and the removal of the blocking pending-reboot check from `ProductUpdate`.

## [3.1.1] - 2026-05-11

### Added

scripts/Modules/util.psm1:

- Added `Test-SPSPendingReboot` to detect pending reboot state using multiple Windows markers (Windows Update, CBS, pending file rename, pending computer rename, and ConfigMgr).

scripts/Modules/sps.util.psm1:

- Added missing `Clear-ComObject` helper used by `Get-SPSLocalVersionInfo` to safely release COM objects.

tests/Modules/util.Tests.ps1:

- Added tests for `Test-SPSPendingReboot` and module export validation for the new helper.
- Added regression tests for `Start-SPSScheduledTask` `TaskPath` parameter support and task path normalization behavior.

tests/Modules/sps.util.Tests.ps1:

- Added regression test ensuring `Start-SPSProductUpdate` no longer exposes `InstallAccount`.

tests/SPSUpdate.Tests.ps1:

- Added assertions for consolidated reboot detection (`Test-SPSPendingReboot`) in ProductUpdate flow.
- Added regression assertion to prevent reintroduction of legacy ProductUpdate MOF cleanup code.

### Fixed

scripts/Modules/util.psm1:

- Fixed `Start-SPSScheduledTask` to support `TaskPath` and use that path when resolving and starting tasks.
- Normalized scheduled task paths to the expected `\<TaskPath>` format for `Get-ScheduledTask` and `Start-ScheduledTask`.
- Changed `Add-SPSScheduledTask` behavior to create or update existing tasks instead of skipping them.

scripts/Modules/sps.util.psm1:

- Fixed runtime failure in `Get-SPSLocalVersionInfo` when `Clear-ComObject` was missing.

scripts/SPSUpdate.ps1:

- Updated ProductUpdate to run update binaries without `InstallAccount`.
- Replaced single reboot check with consolidated reboot detection and detailed marker reporting.
- Removed legacy ProductUpdate `finally` block used for old DSC MOF cleanup.
- Enabled script-level verbose forwarding (`-Verbose`) to downstream module cmdlets.
- Added transcript file path output (`Transcript log file: ...`) at startup for easier log discovery.
- Updated installed SharePoint version output to print `FileVersion` explicitly.

### Changed

Documentation:

- Updated ProductUpdate examples and guidance to remove `InstallAccount` requirement.
- Removed stale references to temporary MOF cleanup after ProductUpdate.

## [3.1.0] - 2026-05-07

### Added

tests/Modules/util.Tests.ps1:

- New Pester test suite for util.psm1 module with 11 test cases
- Module loading validation tests
- Tests for Get-SPSInstalledProductVersion function (callable, return type validation)
- Tests for Add-SPSUpdateEvent function with parameter validation (Message/Source mandatory, EntryType/EventId optional)
- Tests for Invoke-SPSCommand function structure validation (Credential, Server, ScriptBlock parameters)

tests/Modules/sps.util.Tests.ps1:

- Comprehensive Pester test suite for sps.util.psm1 with 4 test cases
- Get-SPSLocalVersionInfo: Tests DisplayVersion fallback when patch metadata is missing
- Start-SPSProductUpdate: Tests file blocking detection with Add-SPSUpdateEvent logging
- Start-SPSProductUpdate: Tests exit code reporting ($setupInstall.ExitCode)
- Start-SPSProductUpdate: Tests service startup type restoration with SP 2015/2019 compatibility

tests/SPSUpdate.Tests.ps1:

- Main script validation test suite with expanded coverage for script structure, task handling, and event logging
- File validation: Existence, file extension matching, PowerShell syntax validation
- Content validation: param block, script version declaration, module imports (util, sps.util), Start-Transcript logging, try-catch error handling, Administrator privilege checks
- Dependency validation: Module files (util.psm1, sps.util.psm1), folders (credentialmanager, Config), sample JSON configuration files
- Configuration file validation: JSON validity, required ConfigurationName property
- Scheduled task validation: task name constants, task existence checks, TaskPath usage, and default action task management patterns
- Error logging validation: catchMessage pattern and Add-SPSUpdateEvent coverage for initialization, task scheduling, product update, credential, and configuration wizard failures

### Fixed

scripts/Modules/util.psm1:

- Get-SPSInstalledProductVersion: Changed return type from string to System.Diagnostics.FileVersionInfo object to enable proper version property access (ProductMajorPart, ProductBuildPart)

scripts/Modules/sps.util.psm1:

- Get-SPSLocalVersionInfo (Lines 393-502): Fixed uninitialized $versionInfo variable by adding proper initialization in all code paths (if block, catch block, fallback assignments)
- Start-SPSProductUpdate (Lines 494-647): Fixed incorrect variable name $setup.ExitCode → $setupInstall.ExitCode for accurate error code reporting
- Start-SPSProductUpdate: Fixed version detection to use ProductMajorPart property instead of non-existent FileMajorPart on FileVersionInfo object
- Start-SPSProductUpdate (Lines 838-851): Fixed service restoration logic to use original $service.StartType from saved JSON instead of forcing all services to Disabled startup type
- Start-SPSProductUpdate (Lines 693-710): Removed misleading exception placeholder from blocked-file error message for clearer error reporting
- Start-SPSProductUpdate: Added credentialed Start-Process execution with Windows identity safety guard for cross-platform compatibility

scripts/SPSUpdate.ps1:

- Added Test-ConfigurationFile to validate JSON structure and required configuration properties before execution
- Centralized scheduled task names and task folder path into script-scoped constants
- Added scheduled task existence checks before recreating full and sequence tasks
- Standardized catch blocks around key operations by composing catchMessage strings and logging failures through Add-SPSUpdateEvent
- Extended task handling in Default mode to use task variables, TaskPath, and event logging consistently

### Changed

.github/workflows/pester.yml:

- Updated PSScriptAnalyzer code quality step to exclude credentialmanager folder (third-party dependency)
- Filter implemented: Get-ChildItem excludes files matching '*credentialmanager*' pattern before analysis
- Improved CI/CD reliability by preventing false positives from third-party code analysis

README.md and wiki/Getting-Started.md:

- Removed outdated SharePointDsc and DSC-based prerequisite/setup guidance
- Updated documentation to describe native `ProductUpdate` execution of SharePoint update binaries
- Replaced the DSC CredSSP example with direct PowerShell CredSSP configuration commands

## [3.0.3] - 2025-11-05

### Changed

scripts\SPSUpdate.ps1:

- Add ErrorAction SilentlyContinue in LanguagePackInstalled registry

### Added

scripts/SPSUpdate_README.md:

- Resolve Documentation Request: Add readme file for offline installation ([issue #8](https://github.com/luigilink/SPSUpdate/issues/8)).

## [3.0.2] - 2025-10-17

### Changed

scripts\SPSUpdate.ps1:

- Cleanup DSC Mof files after installation of Cumulative Updates
- Check patch status before running SPConfig.exe

scripts\Modules\sps.util.psm1:

- Refactor Get-SPSServersPatchStatus and Start-SPSConfigExe functions

## [3.0.1] - 2025-10-17

### Changed

scripts\SPSUpdate.ps1:

- Change credential variable with InstallAccount variable in ProductUpdate Section

scripts\Modules\sps.util.psm1:

- Fix Exception: The term 'Localhost' is not recognized as the name of a cmdlet

## [3.0.0] - 2025-10-17

### Changed

scripts\SPSUpdate.ps1:

- Remove Cleaning up DSC Configuration folder
- Add Get credential from Credential Manager
- BREAKING CHANGE Remove Server Parameter

scripts\Modules\sps.util.psm1:

- Update Start-SPSProductUpdate Function: Remove Server parameter

scripts\Modules\util.psm1

- Remove Unblock-SPSSetupFile and Clear-SPSDscCache functions

Wiki Documentation in repository - Update with new parameters:

- wiki\Getting-Started.md
- wiki\Usage.md

## [2.0.0] - 2025-09-02

### Added

scripts\Modules\sps.util.psm1:

- Add new function Start-SPSProductUpdate

scripts\Modules\util.psm1

- Add new function Get-SPSRebootStatus

### Changed

- Use $PSScriptRoot instead of $MyInvocation.MyCommand.Definition
- Use Exit instead of Break
- Use [System.Diagnostics.FileVersionInfo]::GetVersionInfo instead of Get-Command
- BREAKING CHANGE Remove Clear-SPSLog function
- Remove ADM and use Credential variable

scripts\SPSUpdate.ps1:

- BREAKING CHANGE - Add new parameters: Action and Server

Wiki Documentation in repository - Update with new parameters:

- wiki\Getting-Started.md
- wiki\Home.md
- wiki\Usage.md

README.md

- Add SharePointDsc as prerequisites

## [1.0.1] - 2025-09-01

### Changed

- Update options version in Issue Templates files: 1_bug_report.yml
- Change Write-Verbose CmdLet to Write-Output in scripts\Modules\sps.util.psm1

### Fixed

scripts\SPSUpdate.ps1 and scripts\Modules\util.psm1

- Resolve Cannot add Scheduled Task SPSUpdate-FullScript in SharePoint Task Path ([issue #2](https://github.com/luigilink/SPSUpdate/issues/2)).
- Resolve Start-SPSConfigExeRemote not working on remote servers ([issue #6](https://github.com/luigilink/SPSUpdate/issues/6)).

scripts\SPSUpdate.ps1

- Resolve Set-SPSSideBySideToken function runs when BuildVersion is empty ([issue #4](https://github.com/luigilink/SPSUpdate/issues/4)).

## [1.0.0] - 2023-11-20

### Changed

- README.md
  - Add Requirement and Changelog sections
- release.yml
  - Zip scripts folder and mane it with Tag version
- PULL_REQUEST_TEMPLATE.md => Remove examples and unit test tasks

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml
- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add release.yml file
- Add scripts folder with first version of SPSUpdate
- Wiki Documentation in repository - Add :
  - wiki/Configuration.md
  - wiki/Getting-Started.md
  - wiki/Home.md
  - wiki/Usage.md
  - .github/workflows/wiki.yml
