# SPSUpdate - Release Notes

## [4.2.0] - 2026-06-30

This release adds a near real-time patching dashboard: while a cumulative update is rolled
out across the farm, SPSUpdate records the progress of every phase into a shared status
store and the master assembles a self-contained, auto-refreshing HTML dashboard.

### Added

- Status store and dashboard functions: `Set-SPSUpdateStatus` / `Get-SPSUpdateStatus`
  (atomic per-scope JSON store, each writer owns its file), `Get-SPSStatusCampaignPath`
  (resolves `<root>\<App>-<Env>-<Farm>`), and `Export-SPSUpdateProgressReport` (renders a
  self-contained HTML dashboard with overall state, per-phase sections, colored state
  badges, per-item exit codes and per-sequence percentage; meta-refresh while running).
- New optional `StatusStorePath` config key (UNC share) with a local `Results\status`
  fallback.
- New `-Action ResetStatus` to clear a campaign before a fresh patching round.
- `SPSUpdate.ps1` is instrumented end-to-end: ProductUpdate per server (per-setup-file
  items), the four mount/upgrade sequences (per-database items and a running percentage),
  the Configuration Wizard per server (local and remote), and side-by-side. The master
  regenerates the dashboard on every wait-loop iteration and writes a final completed
  dashboard with auto-refresh off.
- New `Test-SPSUpdateReadiness.ps1` pre-flight check (module, config, DPAPI secret,
  elevation, status store write access, per-server CredSSP reachability). The status store
  check probes write access **both as the current user and as the InstallAccount**, since the
  upgrade sequences run as the service account and only appear on the dashboard when it can
  write to the share.
- The dashboard collapses finished scopes (Done/Skipped) by default and keeps active ones
  expanded (native `<details>`/`<summary>`, accessible, no JS); each collapsed line still
  shows its badge, percentage and an `N/M done` count.
- Real process exit codes are surfaced: the ProductUpdate item's Exit column shows the
  setup.exe code (`0`, `17022` = reboot required, ...), and the Configuration Wizard records
  the psconfig.exe code in its detail (`PSConfig completed (exit 0)`).

### How to use

1. Set `StatusStorePath` to a UNC share writable by the InstallAccount from every server
   (grant it **Modify** on the SMB share and NTFS — the sequence tasks run as that account).
2. Run `Test-SPSUpdateReadiness.ps1` to confirm the environment (both write probes green).
3. `SPSUpdate.ps1 -ConfigFile '<farm>.psd1' -Action ResetStatus` to start a clean campaign.
4. Open `<StatusStorePath>\<App>-<Env>-<Farm>\_dashboard.html` in a browser.
5. Run `-Action ProductUpdate` on each server, then the default master run; watch the
   dashboard update itself.

### Changed

- Bumped the module manifest to `4.2.0` and exported the new functions.

### Notes

- Validated end-to-end on a real three-server Subscription Edition farm with an actual
  cumulative update (binary install, parallel content-database upgrade, and the post-setup
  Configuration Wizard, all reflected live on the dashboard).

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
