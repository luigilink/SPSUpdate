# SPSUpdate - Release Notes

## [4.2.0] - 2026-06-29

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
  elevation, status store write access, per-server CredSSP reachability).

### How to use

1. Set `StatusStorePath` to a UNC share writable by the InstallAccount from every server.
2. `SPSUpdate.ps1 -ConfigFile '<farm>.psd1' -Action ResetStatus` to start a clean campaign.
3. Open `<StatusStorePath>\<App>-<Env>-<Farm>\_dashboard.html` in a browser.
4. Run `-Action ProductUpdate` on each server, then the default master run; watch the
   dashboard update itself.

### Changed

- Bumped the module manifest to `4.2.0` and exported the four new functions.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
