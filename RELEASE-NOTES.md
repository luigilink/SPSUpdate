# SPSUpdate - Release Notes

## [5.3.0] - 2026-10-08

SPSUpdate 5.3.0 harmonizes how every Boolean switch in the environment configuration is parsed.

Previously the `Reboot`, `Remoting` and `Execution` switches (`Reboot.Enable`, `Reboot.Force`,
`Remoting.AllowFallback`, `Execution.InteractiveSequences`) enforced a strict `[bool]` type and
threw on `Reboot.Enable = 1`, while the older flags (`Binaries.ProductUpdate`,
`Binaries.ShutdownServices`, `MountContentDatabase`, `UpgradeContentDatabase`,
`SideBySideToken.Enable`) silently coerced any truthy value — so `1` worked on those, but so did a
typo such as `'false'`, which evaluates to `$true`.

### Changed

- **All nine Boolean configuration switches now behave the same.** Each one accepts `$true` / `$false` **or** the integers `1` / `0` (`1` = `$true`, `0` = `$false`), and rejects every other value (an out-of-range number, or a string such as `'yes'` / `'false'`) with a clear error naming the property. A shared, unit-tested `ConvertTo-SPSConfigBoolean` helper validates and normalizes every switch, and `Test-SPSUpdateReadiness` applies the same contract at pre-flight time (a bad value is reported as a readiness failure). This also hardens the previously unguarded flags against typos. ([#76](https://github.com/luigilink/SPSUpdate/issues/76))

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
