# Change log for SPSUpdate

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
