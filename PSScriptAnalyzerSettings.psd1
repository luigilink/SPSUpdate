@{
    # PSScriptAnalyzer settings for SPSUpdate.
    # Run locally with:
    #   Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    Severity = @('Error', 'Warning')

    # PSUseSingularNouns is disabled defensively: a couple of helpers intentionally use a
    # plural noun because they act on a collection (e.g. Copy-SPSSideBySideFilesRemote
    # operates on the side-by-side file set), mirroring built-in cmdlets such as
    # Get-ChildItem.
    ExcludeRules = @(
        'PSUseSingularNouns'
    )
}
