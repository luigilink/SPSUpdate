# SPSUpdate - Release Notes

## [4.0.0] - 2026-06-29

This is a major modernization release that aligns SPSUpdate with the SPSWeather and
SPSUserSync projects. It is a **breaking** release: the package layout, the configuration
format and the credential storage all change. Review the migration notes below before
upgrading an existing deployment.

### Added

- New `SPSUpdate.Common` PowerShell module (`src/Modules/SPSUpdate.Common`) with a manifest-driven version, a dot-sourcing loader, and a one-file-per-function layout split into `Public/` and `Private/`.
- DPAPI credential store: `Get-SPSSecret` / `Set-SPSSecret` persist the `InstallAccount` as an encrypted SecureString in `Config\secrets.psd1`, replacing the Windows Credential Manager module. `-Action Install` writes the secret and `-Action Uninstall` removes it.
- Tolerant configuration loader: optional keys fall back to safe defaults (`Binaries.ProductUpdate`, `Binaries.ShutdownServices` and `UpgradeContentDatabase` default to `$true`; `MountContentDatabase` and `SideBySideToken.Enable` default to `$false`).
- Repository scaffolding aligned with the other SPS* projects: `.editorconfig`, `.gitattributes` (UTF-8 BOM + CRLF for PowerShell files), `PSScriptAnalyzerSettings.psd1`, and an expanded `.gitignore`.
- Wiki: new `Release-Process` page and `_Sidebar.md` navigation.

### Changed

- **BREAKING** — Project layout moved from `scripts/` to `src/`. The release ZIP now packages the *contents* of `src/`, so the archive extracts straight to `SPSUpdate.ps1`, `Config\` and `Modules\` (no wrapper folder).
- **BREAKING** — Environment configuration moved from JSON to a PowerShell data file (`*.psd1`), read with `Import-PowerShellDataFile`. A single documented template (`Config\CONTOSO-PROD.example.psd1`) lists every option with its possible values inline. Runtime/output files (the ContentDB inventory and logs) stay JSON by design.
- **BREAKING** — The config key `StoredCredential` is renamed to `CredentialKey` and now points at an entry in `Config\secrets.psd1` instead of a Windows Credential Manager target.
- `SPSUpdate.ps1` now imports `SPSUpdate.Common`, derives its version banner from the module manifest, and reads/writes the InstallAccount credential through `Get-SPSSecret`/`Set-SPSSecret`.
- `Add-SPSUpdateEvent` is now self-contained (version/user resolved from the module) and re-points a mis-mapped event source to the `SPSUpdate` log instead of returning silently.
- CI: `release.yml` zips the contents of `src/`; `pester.yml` triggers on `src/**`, `tests/**` and `PSScriptAnalyzerSettings.psd1`, and runs PSScriptAnalyzer against `src/SPSUpdate.ps1` and the `SPSUpdate.Common` module.
- `README.md` trimmed to a short overview with quick links; the wiki (`Home`, `Getting-Started`, `Configuration`, `Usage`) rewritten for the new layout, psd1 config and DPAPI secret store.

### Fixed

- `Invoke-SPSCommand` now fails fast when the CredSSP `New-PSSession` cannot be established (`-ErrorAction Stop` + a clear `throw`) instead of falling back to running the SharePoint scriptblock **locally** on the master server with no session — which previously made PSConfig and side-by-side operations silently target the wrong server. Added an `OpenTimeout` and clearer remote-failure error messages, aligned with the SPSWeather hardening.

### Removed

- **BREAKING** — The bundled third-party `credentialmanager` module (DLLs + manifest) and all `Get-/New-/Remove-StoredCredential` usage.
- The legacy `scripts/` tree, including the flat `util.psm1` / `sps.util.psm1` helpers and the per-farm JSON configs.

### Migration from 3.x

1. Convert each JSON config to a `*.psd1` file (see `Config\CONTOSO-PROD.example.psd1`) and rename `StoredCredential` to `CredentialKey`.
2. Re-run `.\SPSUpdate.ps1 -ConfigFile '<farm>.psd1' -Action Install -InstallAccount (Get-Credential)` **as the service account** to store the credential in `Config\secrets.psd1` (the previous Credential Manager entry is no longer used).
3. Extract the new ZIP on each server; it unpacks to `SPSUpdate.ps1`, `Config\` and `Modules\` directly.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
