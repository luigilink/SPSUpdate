# SPSUpdate - Release Notes

## [5.1.0-preview.1] - 2026-09-22

> **Preview release.** This build is published to validate the new automatic reboot feature
> on a real SharePoint Server SE farm before the 5.1.0 GA. It is **not intended for
> production**. Please test on a non-production farm (or during a controlled maintenance
> window) and report feedback on the [issue tracker](https://github.com/luigilink/SPSUpdate/issues).

This preview adds an optional automatic reboot after a cumulative update install, with
install and reboot schedule windows, and surfaces the reboot on the live dashboard.

### Added

- **Automatic reboot after a CU install (opt-in).** A new `Reboot` config block (off by default) lets a server reboot itself once after the binary install. The reboot is triggered only by the installer "reboot required" exit code (`17022`) - never by Windows pending-reboot registry markers - so it happens at most once per patching campaign. `Reboot.Force` can reboot even when the installer did not ask for one. This mirrors how SharePointDsc handles reboots in PULL mode.
- **Install and reboot schedule windows.** `Binaries.Schedule` and `Reboot.Schedule` (each `{ Days, Time }`) restrict when the install and the reboot may run, validated by the new `Test-SPSScheduleWindow` helper.
- **Reboot lifecycle on the dashboard.** A new `Reboot` phase shows, per server, "Automatic Reboot launched, check the server in a few minutes" then "Server back online after automatic reboot", plus Pending / Skipped / Failed states. A one-shot boot task (`-Action ConfirmReboot`) stamps the reboot as Done, logs it (event source `Restart-SPSServer`, ID 3010) and self-deletes.
- Broader behavioural Pester coverage for the HTML-encode helper, pending-reboot detection and the content-database wrappers.

### Fixed

- `Test-SPSPendingReboot` counts a single `WindowsUpdate\Services\Pending` entry reliably on Windows PowerShell 5.1.

### How to test

1. On a non-production SE farm, enable the feature in your config:
   `Reboot = @{ Enable = $true }` (optionally add a `Schedule = @{ Days = @('sat','sun'); Time = '3:00 AM to 4:00 AM' }`).
2. Dry run first: `.\SPSUpdate.ps1 -ConfigFile '<config>.psd1' -Action ProductUpdate -WhatIf` (no changes made).
3. Then run for real with a CU the farm does not yet have; watch the live dashboard for the **Server reboot** phase.

> **Note:** reboots are per-server. On a farm you remain responsible for not rebooting the sole Distributed Cache host or the last available WFE at the same time. See the wiki.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
