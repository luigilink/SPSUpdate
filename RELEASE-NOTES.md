# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
