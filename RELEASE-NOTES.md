# SPSUpdate - Release Notes

## [5.0.0] - 2026-08-25

This is a **breaking** release: SPSUpdate now targets **SharePoint Server Subscription
Edition only**. SharePoint Server 2016 and 2019 both reached end of support on
14 July 2026.

### Removed

- **BREAKING** — Support for SharePoint Server 2016 and 2019. SPSUpdate now targets SharePoint Server Subscription Edition only.
- The deprecated `Microsoft.SharePoint.PowerShell` PSSnapin path: `SPSUpdate.ps1` and `Invoke-SPSCommand` load the `SharePointServer` module only (idempotently, including inside the remoting HERE-STRING).
- The legacy SharePoint 2013 branches (`FileMajorPart`/`ProductMajorPart -eq 15`: `15\BIN`, the `15.0` registry hive and `OSearch15`) and the 2016/2019/SE cumulative-update detection in `Start-SPSConfigExe`, `Start-SPSConfigExeRemote` and `Start-SPSProductUpdate`.
- The `ProductVersion` parameter of `Get-SPSLocalVersionInfo` (Subscription Edition is resolved unconditionally).

### Changed

- **BREAKING** — Major version bump to `5.0.0`. `Start-SPSConfigExe`/`Start-SPSConfigExeRemote` target the `16.0` hive and `16\BIN` and run `Upgrade-SPFarm` unconditionally; `Start-SPSProductUpdate` stops `OSearch16`.

### Migration

- Users still running SharePoint Server 2016 or 2019 must use the previous major release **v4.2.0**. In particular, generating the ContentDatabase inventory (`-Action InitContentDB`) on a 2019 source farm as part of a 2019 → Subscription Edition migration must be done with v4.2.0.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
