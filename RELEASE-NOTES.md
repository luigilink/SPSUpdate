# SPSUpdate - Release Notes

## [3.2.1] - 2026-06-11

### Changed

scripts/Modules/sps.util.psm1:

- `Initialize-SPSContentDbJsonFile` now distributes content databases across the four sequences using a **Longest Processing Time First (LPT)** algorithm based on `DiskSizeRequired`, instead of splitting them evenly by count (`floor(count / 4)`). Sequences are now balanced by total database size so parallel upgrade workloads finish closer to the same time.
- `Initialize-SPSContentDbJsonFile` now prints a distribution report to the transcript showing the count, total size (MB) and percentage for each of the four sequences.
- `Initialize-SPSContentDbJsonFile` now also writes a timestamped snapshot of the inventory (`<basename>_yyyy-MM-dd_HH-mm-ss.json`) next to the canonical file each time it runs. The canonical file (consumed by `SPSUpdate.ps1`) is still overwritten in place, while the dated snapshots accumulate in `scripts/Config/` so previous inventories can be reviewed or restored. Snapshot failures are logged via `Write-Verbose` and never block the canonical write.
- `Start-SPSProductUpdate` now invokes the SharePoint patch setup with `/passive` instead of `/quiet`. `/passive` still runs the patch without user interaction but displays a progress UI, which gives administrators visibility on the installation progress when the script is run interactively. Behavior of the returned exit code and the post-install service-restoration logic is unchanged.

scripts/SPSUpdate.ps1:

- Bumped `$SPSUpdateVersion` to `3.2.1`.

### Fixed

scripts/Modules/sps.util.psm1:

- Fixed `Initialize-SPSContentDbJsonFile` edge case where fewer than 4 content databases caused `groupSize` to evaluate to `0`, dumping every database into `SPContentDatabase4` and leaving `SPContentDatabase1..3` empty.

### Tests

tests/Modules/sps.util.Tests.ps1:

- Added Pester tests for `Initialize-SPSContentDbJsonFile` covering: no file written when `Get-SPContentDatabase` returns `$null`, fair distribution of fewer than 4 databases (regression for the `floor(count / 4)` bug), LPT balancing by size (the largest database lands alone in its sequence), and the `SPContentDatabase1..4` JSON property contract consumed by `SPSUpdate.ps1`.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
