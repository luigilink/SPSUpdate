# SPSUpdate - Release Notes

## [5.1.0] - 2026-10-06

SPSUpdate 5.1.0 is a major feature release, validated end to end on a real SharePoint Server
Subscription Edition farm (binary install, parallel content-database upgrade, Configuration Wizard,
automatic reboot and the live patching dashboard). It introduces a redesigned near real-time
dashboard, standalone IIS hosting for that dashboard, an optional automatic reboot after a CU,
a CredSSP-to-Negotiate remoting fallback, richer readiness checks, optional interactive sequence
windows, and a fix for the remote Configuration Wizard false failure.

### Added

- **Redesigned near real-time dashboard (three server-oriented cards).** ([#47](https://github.com/luigilink/SPSUpdate/issues/47))
  - **Binaries Installation** - one row per farm server: status, SharePoint patch status, installed build and completion time.
  - **SharePoint Configuration Wizard** - the same, plus a detail column.
  - **Content Databases** - one row per database: web application, SQL instance, size, sequence, upgrade status and processing state.
  - The farm baseline is **pre-filled at campaign start** from `Get-SPServer`, so the whole farm is visible up front. The live farm status is refreshed at key transitions (pre-patch baseline, after the Configuration Wizard, and the final render), so a successful campaign returns to `No Action Required` / `No update pending` with no stale inconsistency banner. Patch status and role use short Central Administration labels (for example `Upgrade Required`, `Application with Search`) via the new public helpers `ConvertTo-SPSPatchStatusLabel` and `ConvertTo-SPSRoleLabel`. A new dark/light theme (aligned with the SPSConfigKit DSC dashboard) adds a summary donut, KPIs, status pills and a theme toggle. ([#51](https://github.com/luigilink/SPSUpdate/issues/51))
- **Standalone IIS dashboard hosting helper.** A new idempotent `New-SPSDashboardSite.ps1` (in `src/`) provisions the dashboard hosting target on an IIS/pull server — folder, SMB share (Modify for the write accounts), NTFS permissions, a static-file `web.config`, and either a dedicated IIS site or a sub-application under an existing site. It has no dependency on the `SPSUpdate.Common` module, so it can be copied on its own to the IIS server. `Test-SPSUpdateReadiness.ps1` also checks the optional `Dashboard.OutputPath` (exists, writable, and warns on a master-local path rather than a shared UNC path). A new wiki page, *Hosting the dashboard on IIS*, documents the validated setup. ([#49](https://github.com/luigilink/SPSUpdate/issues/49))
- **Per-farm dashboard file name and optional IIS hosting.** `Dashboard.OutputPath` writes the dashboard into an existing IIS-served folder, and the file name is derived per farm (`<App>-<Env>-<Farm>-dashboard.html`) so several farms (INT / Preprod / PROD) can share one folder. `ResetStatus` archives the previous dashboard to `history\<name>_<timestamp>.html`.
- **Automatic reboot after a CU install (opt-in).** A new `Reboot` config block (off by default) lets a server reboot itself once after the binary install, triggered only by the installer "reboot required" exit code (`17022`) - never by Windows pending-reboot registry markers - with `Binaries.Schedule` / `Reboot.Schedule` windows, the reboot state surfaced on the dashboard, and a one-shot boot task (`-Action ConfirmReboot`) that stamps completion and self-deletes.
- **CredSSP-to-Negotiate fallback for remote cmdlets (opt-in).** `Remoting.AllowFallback` (off by default) lets `Invoke-SPSCommand` fall back to `Negotiate` when the CredSSP session cannot be opened, with a clear warning that double-hop steps may fail without Kerberos delegation. `Test-SPSUpdateReadiness` runs a real CredSSP session test per server and checks the local WinRM prerequisites first. ([#39](https://github.com/luigilink/SPSUpdate/issues/39), [#44](https://github.com/luigilink/SPSUpdate/issues/44))
- **Optional interactive sequence windows (opt-in).** `Execution.InteractiveSequences` (off by default) runs the four parallel content-database sequences in visible Windows PowerShell windows on an attended run, instead of hidden scheduled tasks. Unattended/scheduled runs always use scheduled tasks. ([#42](https://github.com/luigilink/SPSUpdate/issues/42))

### Fixed

- **Remote Configuration Wizard false `exit code -1` failure.** `Start-SPSConfigExe` and `Start-SPSConfigExeRemote` now handle the `psconfig.exe` exit code identically; a new `Resolve-SPSWizardOutcome` helper re-checks the authoritative per-server patch status, so a non-zero code from a later psconfig sub-command on an already-upgraded server is reported as Done (with a warning) instead of a false failure. ([#40](https://github.com/luigilink/SPSUpdate/issues/40))
- **`-Action ProductUpdate -WhatIf` transcript and status.** A dry run no longer prints a red `Stop-Transcript` error and no longer marks the server **Done / patched** on the dashboard: the scope is reported `Pending` with build and completion time cleared, keyed on the real `-WhatIf` mode. The `Stop-Transcript` call also no longer throws on Windows PowerShell 5.1 (which does not expose `-WhatIf` on that cmdlet). ([#53](https://github.com/luigilink/SPSUpdate/issues/53), [#55](https://github.com/luigilink/SPSUpdate/issues/55))
- **Dashboard correctness.** The Content Databases card no longer shows a stale `Upgrade available` / false inconsistency banner on the `ResetStatus` waiting dashboard; the Configuration Wizard card no longer shows a stale `Skipped` for servers queued behind the master; and a server's reboot state (failed / completed / pending) is now always visible on the Binaries card. ([#57](https://github.com/luigilink/SPSUpdate/issues/57), [#62](https://github.com/luigilink/SPSUpdate/issues/62), [#60](https://github.com/luigilink/SPSUpdate/issues/60))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
