# SPSUpdate

![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSUpdate.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSUpdate/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSUpdate.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSUpdate is a PowerShell script tool designed to install cumulative updates in your SharePoint environment.

[Download the latest release, Click here!](https://github.com/luigilink/SPSUpdate/releases/latest)

## Requirements

### PowerShell 5.1 or later

SPSUpdate no longer depends on a DSC module.
Use PowerShell 5.1 or later on each SharePoint server where you run the script.
The script relies on standard PowerShell remoting, scheduled tasks, Credential Manager integration, and native SharePoint update binaries.
This is discussed further on the [SPSUpdate Wiki Getting-Started](https://github.com/luigilink/SPSUpdate/wiki/Getting-Started)

## CredSSP

Impersonation is handled using the `Invoke-Command` cmdlet in PowerShell, together with the creation of a remote session via `New-PSSession`. In the SPSUpdate script, we authenticate as the InstallAccount and specify CredSSP as the authentication mechanism. This is explained further in the [SPSUpdate Wiki Getting-Started](https://github.com/luigilink/SPSUpdate/wiki/Getting-Started)

## ProductUpdate

The `ProductUpdate` action runs the SharePoint update binaries directly on the local server. You only need the update files accessible on that server.

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSUpdate Wiki](https://github.com/luigilink/SPSUpdate/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
