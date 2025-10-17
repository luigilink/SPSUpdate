# Change log for SPSUpdate

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
