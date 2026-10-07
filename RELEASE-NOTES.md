# SPSUpdate - Release Notes

## [5.2.0] - 2026-10-07

SPSUpdate 5.2.0 refines the automatic reboot and the live patching dashboard introduced in 5.1.0.
The one-shot reboot-confirmation boot task now runs as `NT AUTHORITY\SYSTEM` (no stored
credential), a deferred reboot already performed out-of-band is reconciled instead of restarting
the server again, and the Binaries Installation card shows the real live patch status right after a
`ProductUpdate` installs a cumulative update.

### Changed

- **Reboot-confirmation task runs as SYSTEM.** The one-shot `SPSUpdate-RebootConfirm` boot task now runs as `NT AUTHORITY\SYSTEM` instead of the farm InstallAccount decrypted from `secrets.psd1`, removing the stored-credential dependency that could abort the reboot at task registration (`0x8007052E`) and decoupling the reboot from password rotation. `Add-SPSScheduledTask` gains a `-RunAsSystem` switch (mutually exclusive with `-ExecuteAsCredential`). Because a SYSTEM task reaches a UNC status store as the computer account, grant the farm computer accounts (e.g. `Domain Computers`) Modify on the share — add them to `New-SPSDashboardSite.ps1 -WriteAccounts`; `-Action ConfirmReboot` logs a clear, actionable warning when the grant is missing. ([#64](https://github.com/luigilink/SPSUpdate/issues/64))

### Added

- **Out-of-band reboot reconciliation.** A deferred automatic reboot that was already performed outside SPSUpdate (a manual restart or a Windows Update reboot) is now reconciled instead of restarting the server again: when a `.pending` reboot request predates the server's last boot time, `Invoke-SPSAutomaticReboot` marks the Reboot phase `Done` ("Reboot already completed out-of-band"), clears the pending marker and skips the restart. A fresh reboot required by an install performed in the same run is unaffected. ([#68](https://github.com/luigilink/SPSUpdate/issues/68))
- **Live patch status after `ProductUpdate`.** `-Action ProductUpdate` now refreshes the installed server's live patch status on the Binaries Installation card after the cumulative update is installed, so the column reflects the real post-install state (typically `Upgrade Required` until the Configuration Wizard runs) instead of keeping the pre-install value until the next `Default` run. It reuses the same master-side patch-status read as the `Default` baseline (no remoting) and is status-only. A failed read preserves the last-known-good value. ([#59](https://github.com/luigilink/SPSUpdate/issues/59))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
