# SPSUpdate - Release Notes

## [4.4.0] - 2026-10-07

SPSUpdate 4.4.0 backports to the **`4.x` maintenance line** (SharePoint Server 2016 / 2019 and
Subscription Edition) three fixes already shipped on the `5.x` line in **v5.2.0**. The only
difference from the `5.x` line remains how the SharePoint cmdlets are loaded (the legacy
`Microsoft.SharePoint.PowerShell` snap-in on 2016/2019, the `SharePointServer` module on Subscription
Edition); the ported logic is otherwise identical.

> ⚠️ SharePoint Server 2016 and 2019 reached **Microsoft end of support on 14 July 2026** and no
> longer receive security updates. This line restores SPSUpdate **tooling compatibility** only; it
> does **not** restore vendor support. Plan a migration to Subscription Edition (and the `5.x` line).

### Changed

- **Reboot-confirm boot task runs as `NT AUTHORITY\SYSTEM`.** The one-shot `SPSUpdate-RebootConfirm` task (automatic reboot) no longer depends on the farm InstallAccount decrypted from `secrets.psd1`, removing a stored-credential failure at task registration (`0x8007052E`) and decoupling the reboot from password rotation. `Add-SPSScheduledTask` gains a `-RunAsSystem` switch. Because a `SYSTEM` task reaches a UNC status store as the computer account, the share must grant the farm computer accounts (e.g. `Domain Computers`) Modify; `-Action ConfirmReboot` logs a clear, actionable warning and retries on the next boot when the grant is missing. ([#64](https://github.com/luigilink/SPSUpdate/issues/64))

### Added

- **Live Patch Status after a CU install.** `-Action ProductUpdate` now refreshes the installed server's Patch Status on the Binaries Installation card after a real install, so the column reflects the post-install state (typically `Upgrade Required` until the Configuration Wizard runs) instead of keeping the pre-install value until the next `Default` run. Status-only, no remoting, and a failed read preserves the last-known-good value. ([#59](https://github.com/luigilink/SPSUpdate/issues/59))
- **Out-of-band reboot reconciliation.** A deferred automatic reboot already performed out-of-band (a manual restart or a Windows Update reboot) is reconciled instead of restarting the server again: when a `.pending` reboot request predates the server's last boot time, `Invoke-SPSAutomaticReboot` marks the Reboot phase `Done`, clears the pending marker and skips the restart. A fresh reboot required by an install performed in the same run is unaffected. ([#68](https://github.com/luigilink/SPSUpdate/issues/68))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
