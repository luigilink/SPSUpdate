# SPSUpdate

![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSUpdate.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSUpdate/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSUpdate.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSUpdate is a PowerShell script tool designed to install cumulative updates in your SharePoint environment.

[Download the latest release, Click here!](https://github.com/luigilink/SPSUpdate/releases/latest)

## Requirements

### Windows Management Framework 5.0

Required because this module now implements class-based resources.
Class-based resources can only work on computers with Windows rManagement Framework 5.0 or above.
The preferred version is PowerShell 5.1 or higher, which ships with Windows 10 or Windows Server 2016.
This is discussed further on the [SPSUpdate Wiki Getting-Started](https://github.com/luigilink/SPSUpdate/wiki/Getting-Started)

## CredSSP

Impersonation is handled using the `Invoke-Command` cmdlet in PowerShell, together with the creation of a "remote" session via `New-PSSession`. In the SPSUpdate script, we authenticate as the InstallAccount and specify CredSSP as the authentication mechanism. This is explained further in the [SPSUpdate Wiki Getting-Started](https://github.com/luigilink/SPSUpdate/wiki/Getting-Started)

## SharePointDsc

SPProductUpdate is the resource DSC of SharePointDsc Module. This resource is used to perform the update step of installing SharePoint updates, like Cumulative Updates and Service Packs.
The installation of SharePointDsc is explained further in the [Installation section](https://github.com/dsccommunity/SharePointDsc?tab=readme-ov-file#installation)

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSUpdate Wiki](https://github.com/luigilink/SPSUpdate/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
