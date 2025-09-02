# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
