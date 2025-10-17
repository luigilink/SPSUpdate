# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
