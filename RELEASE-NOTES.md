# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
