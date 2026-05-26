# SPSUpdate - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
