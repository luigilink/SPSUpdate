# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
