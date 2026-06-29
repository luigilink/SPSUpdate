# SPSUpdate - Release Notes

## [4.1.0] - 2026-06-29

This release adds a self-contained HTML report for the ContentDatabase inventory, in the
same spirit as the SPSUserSync reports. It builds on the v4.0.0 modernization and is fully
backward compatible.

### Added

- New public function `Export-SPSUpdateDbReport` that renders the ContentDatabase inventory (`<App>-<Env>-<Farm>-ContentDBs.json`) as a self-contained, offline HTML report: summary cards (total databases, total size, balance spread), the per-sequence LPT distribution (count / size / percentage bars), and a sortable, filterable table of every database. Inventories generated before v4.1.0 (no size) still render and fall back to distributing by database count.
- `SPSUpdate.ps1` now writes the HTML report under a new `Results\` folder whenever the inventory is (re)generated (the `InitContentDB` action and the Default-mode prime). Report failures warn but never block the run.
- Private report helpers: `ConvertTo-SPSHtmlEncoded`, `Get-SPSReportCardHtml`, `Get-SPSReportHtmlHead`, `Get-SPSReportDistributionHtml`, `Get-SPSReportHtmlScript`.

### Changed

- `Initialize-SPSContentDbJsonFile` now persists `SizeInBytes` and `SizeInMB` for each database in the inventory JSON. This is backward compatible: the mount/upgrade flow still reads only `Name`, `WebAppUrl` and `Server`.
- Bumped the module manifest to `4.1.0` and exported `Export-SPSUpdateDbReport`.

### Notes

- An inventory produced by v4.0.0 (without size) renders correctly; regenerate it with `-Action InitContentDB` to get the size columns and size-based balancing in the report.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
