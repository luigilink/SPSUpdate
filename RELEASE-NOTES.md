# SPSUpdate - Release Notes

## [5.4.0] - 2026-11-09

SPSUpdate 5.4.0 hardens a cumulative-update campaign on a real farm. It was validated on a
four-server Subscription Edition farm (October 2026 CU, 18 content databases): binaries on every
server, Configuration Wizard, parallel database upgrade, and a dashboard that reaches 100 %.

There is no change to the `.psd1` configuration or to the package layout: copy the new files over
the existing ones.

### Fixed

- **SideBySide token: transient update conflicts are retried.** `Set-SPSSideBySideToken` no longer
  fails on the first `SPWebService.Update()` conflict raised while `PSCONFIG` is writing to the
  configuration database. It retries with a bounded policy (6 attempts, 15 seconds apart),
  reloading the web service between attempts. Only update conflicts are retried; any other error
  still fails immediately, and a conflict that persists through the budget is reported as a failure.
  ([#79](https://github.com/luigilink/SPSUpdate/issues/79))
- **Content databases added after `InitContentDB` are no longer silently ignored.** The cached
  inventory was never compared with SharePoint, so a database created later was missing from the
  dashboard and from the mount/upgrade sequences. The new public function
  `Compare-SPSContentDbInventory` now backs two checks: the Default master run logs a warning and
  an event-log entry listing the attached databases missing from the inventory, and
  `Test-SPSUpdateReadiness.ps1` reports the same as a WARN (it reads the inventory from the script
  `Config` folder, like `SPSUpdate.ps1`). Inventory databases that are not attached are only
  reported, since they are expected for an inventory imported from a source farm; do not regenerate
  such an inventory. `-Action InitContentDB` now also refreshes the content database list of an
  existing campaign dashboard. ([#85](https://github.com/luigilink/SPSUpdate/issues/85))
- **Dashboard: a server is no longer counted twice in `Done / Skipped`.** A completed reboot is not
  a separate unit anymore (it stays visible as the *Rebooted* pill), while a pending, running or
  failed reboot still counts so a campaign cannot show a false 100 %.
  ([#86](https://github.com/luigilink/SPSUpdate/issues/86))

### Changed

- **Dashboard completion percentage.** A `Running` unit now counts as half a unit, and the blue arc
  of the ring uses the same weight, so the percentage moves during the binary installation instead
  of staying at `0%`. 100 % and the green colour remain reserved for a campaign where every unit is
  Done or Skipped. ([#83](https://github.com/luigilink/SPSUpdate/issues/83))
- **Documentation.** The wiki `Configuration` page explains how to run the cumulative update from a
  UNC share without the interactive *Open File - Security Warning* prompt (Local intranet zone by
  GPO or registry); keeping the binaries on a local drive remains the recommendation.
  ([#81](https://github.com/luigilink/SPSUpdate/issues/81))

### Known issue

- The Patch Status shown on the Binaries card right after `-Action ProductUpdate` can be stale
  (the configuration-database cache is not refreshed by a local install). Run `Get-SPProduct -Local`
  on the server, or let the Default run refresh it. A fix is pending a live validation.
  ([#71](https://github.com/luigilink/SPSUpdate/issues/71))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
