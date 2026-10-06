# SPSUpdate - Release Notes

## [4.3.0] - 2026-10-06

SPSUpdate 4.3.0 brings the full SPSUpdate 5.1.0 feature set to the **`4.x` maintenance line**, which
supports **SharePoint Server 2016 and 2019** in addition to Subscription Edition. The only
difference from the `5.x` line is how the SharePoint cmdlets are loaded (the legacy
`Microsoft.SharePoint.PowerShell` snap-in on 2016/2019, the `SharePointServer` module on Subscription
Edition); everything else — the redesigned near real-time dashboard, automatic reboot, IIS dashboard
hosting, CredSSP-to-Negotiate fallback, readiness checks, interactive sequence windows and the
Configuration Wizard exit-code fix — is identical to 5.1.0.

> ⚠️ SharePoint Server 2016 and 2019 reached **Microsoft end of support on 14 July 2026** and no
> longer receive security updates. This line restores SPSUpdate **tooling compatibility** only; it
> does **not** restore vendor support. Plan a migration to Subscription Edition (and the `5.x` line).

### Added

- **SharePoint 2016 / 2019 compatibility.** The SharePoint cmdlets are loaded through the legacy `Microsoft.SharePoint.PowerShell` snap-in on 2016/2019 and the `SharePointServer` module on Subscription Edition, both locally and in remote sessions. The product version is detected automatically at runtime, so **no configuration change** is required. As a safety check on this multi-version line, `Start-SPSProductUpdate` fails fast when the update package's product line (2016/2019/SE) does not match the installed SharePoint line, before stopping any service or launching the installer. ([#38](https://github.com/luigilink/SPSUpdate/issues/38))
- **Redesigned near real-time dashboard (three server-oriented cards).** Binaries Installation, SharePoint Configuration Wizard and Content Databases, pre-filled at campaign start and refreshed live at key transitions, with Central Administration labels, a summary donut, KPIs, status pills and a dark/light theme. Optional IIS hosting via `Dashboard.OutputPath` and the standalone `New-SPSDashboardSite.ps1` helper. ([#47](https://github.com/luigilink/SPSUpdate/issues/47), [#49](https://github.com/luigilink/SPSUpdate/issues/49), [#51](https://github.com/luigilink/SPSUpdate/issues/51))
- **Automatic reboot after a CU install (opt-in).** A new `Reboot` config block (off by default) reboots a server once after the binary install, triggered only by the installer "reboot required" exit code (`17022`), with `Binaries.Schedule` / `Reboot.Schedule` windows, the reboot state surfaced on the dashboard, and a one-shot boot task (`-Action ConfirmReboot`). ([#34](https://github.com/luigilink/SPSUpdate/issues/34))
- **CredSSP-to-Negotiate fallback for remote cmdlets (opt-in).** `Remoting.AllowFallback` lets `Invoke-SPSCommand` fall back to `Negotiate` when CredSSP cannot be opened, with a double-hop warning. `Test-SPSUpdateReadiness` runs a real CredSSP session test per server and checks the local WinRM prerequisites first. ([#39](https://github.com/luigilink/SPSUpdate/issues/39), [#44](https://github.com/luigilink/SPSUpdate/issues/44))
- **Optional interactive sequence windows (opt-in).** `Execution.InteractiveSequences` runs the four parallel content-database sequences in visible Windows PowerShell windows on an attended run. ([#42](https://github.com/luigilink/SPSUpdate/issues/42))

### Fixed

- **Remote Configuration Wizard false `exit code -1` failure.** A new `Resolve-SPSWizardOutcome` helper re-checks the authoritative per-server patch status, so a non-zero code from a later psconfig sub-command on an already-upgraded server is reported as Done (with a warning) instead of a false failure. ([#40](https://github.com/luigilink/SPSUpdate/issues/40))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
