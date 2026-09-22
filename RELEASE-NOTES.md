# SPSUpdate - Release Notes

## [5.1.0] - 2026-09-22

This release adds an optional automatic reboot after a cumulative update install, with
install and reboot schedule windows, and surfaces the reboot on the live dashboard.

### Added

- **Automatic reboot after a CU install (opt-in).** A new `Reboot` config block (off by default) lets a server reboot itself once after the binary install. The reboot is triggered only by the installer "reboot required" exit code (`17022`) - never by Windows pending-reboot registry markers - so it happens at most once per patching campaign. `Reboot.Force` can reboot even when the installer did not ask for one. This mirrors how SharePointDsc handles reboots in PULL mode.
- **Install and reboot schedule windows.** `Binaries.Schedule` and `Reboot.Schedule` (each `{ Days, Time }`) restrict when the install and the reboot may run, validated by the new `Test-SPSScheduleWindow` helper.
- **Reboot lifecycle on the dashboard.** A new `Reboot` phase shows, per server, "Automatic Reboot launched, check the server in a few minutes" then "Server back online after automatic reboot", plus Pending / Skipped / Failed states. A one-shot boot task (`-Action ConfirmReboot`) stamps the reboot as Done, logs it (event source `Restart-SPSServer`, ID 3010) and self-deletes.
- Broader behavioural Pester coverage for the HTML-encode helper, pending-reboot detection and the content-database wrappers.

### Fixed

- `Test-SPSPendingReboot` counts a single `WindowsUpdate\Services\Pending` entry reliably on Windows PowerShell 5.1.

> **Note:** reboots are per-server. On a farm you remain responsible for not rebooting the sole Distributed Cache host or the last available WFE at the same time. See the wiki.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
