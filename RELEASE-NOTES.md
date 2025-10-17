# SPSUpdate - Release Notes

## [3.0.2] - 2025-10-17

### Changed

scripts\SPSUpdate.ps1:

- Cleanup DSC Mof files after installation of Cumulative Updates
- Check patch status before running SPConfig.exe

scripts\Modules\sps.util.psm1:

- Refactor Get-SPSServersPatchStatus and Start-SPSConfigExe functions

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
