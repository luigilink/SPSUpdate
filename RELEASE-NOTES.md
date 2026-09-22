# SPSUpdate - Release Notes

## [5.0.1] - 2026-09-21

This patch fixes the near real-time patching dashboard on farms that have no content
databases (for example a dedicated search farm).

### Fixed

- On a farm without content databases, the mount/upgrade sequences were shown as **Failed** with "Cannot bind argument to parameter 'Name' because it is an empty string." The inventory generator (`Initialize-SPSContentDbJsonFile`) now always writes a valid file with four (possibly empty) sequences; the master run skips the mount/upgrade sequences entirely when there is no content database (so the dashboard shows only ProductUpdate, the Configuration Wizard and side-by-side); and each sequence sub-run defensively ignores empty entries.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
