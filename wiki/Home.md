# SPSUpdate Wiki

**SPSUpdate** is a PowerShell tool that installs SharePoint Server cumulative updates and runs the post-setup Configuration Wizard (PSConfig) across a farm. It is compatible with all supported on-premises versions of SharePoint Server (2016 to Subscription Edition) and requires only PowerShell 5.1 or later — there is no DSC dependency.

SPSUpdate installs the update binaries, mounts and/or upgrades content databases in parallel via scheduled tasks, runs PSConfig on the local and remote servers over **CredSSP remoting**, and configures the side-by-side patching token for zero-downtime upgrades.

## Key features

- Install cumulative update binaries locally (`ProductUpdate`)
- Parallel content-database mount/upgrade across 4 sequences (LPT-balanced by size)
- Post-setup Configuration Wizard (PSConfig) on local and remote servers via CredSSP
- Side-by-side token configuration for zero-downtime patching
- Configuration as a PowerShell data file (`*.psd1`)
- Service credential stored as a DPAPI-encrypted `secrets.psd1` — no third-party module
- Windows Event Log instrumentation (dedicated `SPSUpdate` log)
- Self-contained `SPSUpdate.Common` PowerShell module (manifest-driven version)

## Architecture overview

```
        SPSUpdate.ps1  (entry point, scheduled tasks)
               |  imports
               v
        SPSUpdate.Common  (PowerShell module: Public/ + Private/)
               |  CredSSP remoting (Invoke-Command / New-PSSession)
               v
   Each SharePoint farm server  -->  binaries install / PSConfig / DB upgrade
```

The credential used for remoting and scheduled tasks is read from `Config\secrets.psd1` (DPAPI), and every run writes lifecycle entries to the `SPSUpdate` Windows Event Log.

## Pages

- [Getting Started](Getting-Started) — prerequisites, CredSSP, installation, first run
- [Configuration](Configuration) — `*.psd1` environment config and `secrets.psd1` explained
- [Usage](Usage) — actions, sequences, scheduling, output and the event log
- [Release Process](Release-Process) — for maintainers: how to ship a new version

## Project links

- [Source repository](https://github.com/luigilink/SPSUpdate)
- [Latest release](https://github.com/luigilink/SPSUpdate/releases/latest)
- [Issues](https://github.com/luigilink/SPSUpdate/issues)
- [Changelog](https://github.com/luigilink/SPSUpdate/blob/main/CHANGELOG.md)
