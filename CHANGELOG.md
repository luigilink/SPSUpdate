# Change log for SPSUpdate

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.1] - 2026-05-11

### Added

scripts/Modules/util.psm1:

- Added `Test-SPSPendingReboot` to detect pending reboot state using multiple Windows markers (Windows Update, CBS, pending file rename, pending computer rename, and ConfigMgr).

scripts/Modules/sps.util.psm1:

- Added missing `Clear-ComObject` helper used by `Get-SPSLocalVersionInfo` to safely release COM objects.

tests/Modules/util.Tests.ps1:

- Added tests for `Test-SPSPendingReboot` and module export validation for the new helper.

tests/Modules/sps.util.Tests.ps1:

- Added regression test ensuring `Start-SPSProductUpdate` no longer exposes `InstallAccount`.

tests/SPSUpdate.Tests.ps1:

- Added assertions for consolidated reboot detection (`Test-SPSPendingReboot`) in ProductUpdate flow.
- Added regression assertion to prevent reintroduction of legacy ProductUpdate MOF cleanup code.

### Fixed

scripts/Modules/sps.util.psm1:

- Fixed runtime failure in `Get-SPSLocalVersionInfo` when `Clear-ComObject` was missing.

scripts/SPSUpdate.ps1:

- Updated ProductUpdate to run update binaries without `InstallAccount`.
- Replaced single reboot check with consolidated reboot detection and detailed marker reporting.
- Removed legacy ProductUpdate `finally` block used for old DSC MOF cleanup.

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
