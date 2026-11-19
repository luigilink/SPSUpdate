# SPSUpdate - Release Notes

## [5.5.0] - 2026-11-19

SPSUpdate 5.5.0 adds an optional service shutdown profile that shortens the installation of a
cumulative update on SharePoint Server Subscription Edition, and makes the service handling around
the installer safe.

It was validated on a four-server Subscription Edition farm with the November 2026 CU (KB5002945,
`16.0.20326.20278`): two application servers with search and two front-ends with the Distributed
Cache. The binaries took **18 to 25 minutes per server** (installer, service shutdown and restore
included), the 18 content databases were upgraded in about 6 minutes, the whole `Default` run took
24 minutes and the dashboard ended at 100 %. The `.psd1` configuration stays compatible: the new
keys are optional and the default behaviour is unchanged.

### Added

- **`Extended` service shutdown profile.** On Subscription Edition the installer can take hours when
  the SharePoint and IIS services are still running (files in use in the GAC). With
  `Binaries.ShutdownServices = $true`, `Binaries.ServiceShutdownProfile = 'Extended'` stops, in the
  order recommended by Stefan Gossner, `SPTimerV4`, `SPTraceV4`, `SPAdminV4`, `W3SVC`, `OSearch16`,
  `SPSearchHostController` and `SPCache`, and restarts them in reverse order. Only the services that
  exist and run on the server are touched, so it follows the role of each server. `Basic` (the
  default) keeps the historical list, so existing configurations behave as before.
  ([#90](https://github.com/luigilink/SPSUpdate/issues/90))
- **Graceful Distributed Cache stop.** `Binaries.GracefulStopDistributedCache` (Extended only,
  default `$false`) gracefully stops the Distributed Cache host for zero downtime patching, with a
  fallback to a normal stop. Patch one Distributed Cache server at a time.
  ([#90](https://github.com/luigilink/SPSUpdate/issues/90))
- New public functions `Stop-SPSUpdateServices` and `Restore-SPSUpdateServices`. The original state
  of the services is saved to `Results\SPSUpdate-ServicesState_<server>_<date>.json` **before** the
  first service is stopped, and a service that cannot be stopped or restored raises a warning and an
  event log entry. ([#90](https://github.com/luigilink/SPSUpdate/issues/90))

### Fixed

- **Services are no longer left disabled and stopped.** `-Action ProductUpdate` restores the services
  when the installer fails, when the shutdown itself fails half way, or when the run is interrupted.
  The next `ProductUpdate` restores them from the saved state file before anything else (also when the
  package is already installed or outside the install window), and `Restore-SPSUpdateServices
  -StateFolder` does it by hand. If the restore fails, the server is reported as Failed and no
  automatic reboot is started; a second `ProductUpdate` started while one is running on the same
  server refuses to start instead of touching its services.
  ([#90](https://github.com/luigilink/SPSUpdate/issues/90))
- **Stale Patch Status after an install.** `-Action ProductUpdate` refreshes the local product cache
  (`Get-SPProduct -Local`) before reading the Patch Status, so the Binaries card no longer keeps the
  pre-install value. The status can still change afterwards as the farm settles (for example from
  `Upgrade Blocked` to `Upgrade Available`), and the `Default` run reads it again.
  ([#71](https://github.com/luigilink/SPSUpdate/issues/71))

### Upgrade notes

- Keep the update binaries on a **local drive** of each server. Running the `.exe` from a UNC share
  shows an interactive security prompt after the services have been stopped; the wiki explains how
  to avoid it.
- Exclude the SharePoint folders from the antivirus real-time scan during the installation.
- Try `Extended` on one server first and note the duration. `GracefulStopDistributedCache` is
  meant for farms with several Distributed Cache hosts, patched one at a time.
- Not yet exercised on a live farm: the recovery after an interrupted update (covered by tests), and
  the retry of SideBySide update conflicts introduced in 5.4.0 (it only happens while PSCONFIG writes
  to the configuration database).

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
